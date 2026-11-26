// GM Agent · 引擎桥（进程内 dylib 模式）
// 不用 fork/exec：把 gm-engine 编成 dylib，dlopen 后在后台线程跑 gm_engine_main，
// stdin/stdout 通过 socketpair 重定向。iOS 上不需要任何可执行特权。
#import "GMBridge.h"
#import "GMJSON.h"
#import "GMLog.h"

#include <dlfcn.h>
#include <unistd.h>
#include <signal.h>
#include <pthread.h>
#include <sys/socket.h>

typedef int (*GMEngineMainFn)(int, char **);
typedef int (*GMHostToolFn)(const char *, const char *, char **);
typedef void (*GMSetHostToolFn)(GMHostToolFn);

extern int GMHostToolDispatch(const char *name, const char *args, char **out);

@interface GMBridge () {
    int _toEngineFd;      // 我们写
    int _fromEngineFd;    // 我们读
    NSFileHandle *_toEngine;
    NSFileHandle *_fromEngine;
    NSMutableDictionary<NSNumber *, void (^)(id, NSError *)> *_pending;
    long long _nextID;
    NSMutableData *_lineBuffer;
    pthread_t _thread;
    BOOL _running;
}
@end

static GMBridge *gBridge = nil;

@implementation GMBridge

+ (instancetype)shared {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gBridge = [[GMBridge alloc] init];
        NSError *e = nil;
        if (![gBridge startWithError:&e]) {
            GMLog(@"shared 启动引擎失败: %@", e.localizedDescription);
        }
    });
    return gBridge;
}

- (instancetype)init {
    if ((self = [super init])) {
        _pending = [NSMutableDictionary dictionary];
        _nextID = 1;
        _lineBuffer = [NSMutableData data];
        _toEngineFd = -1;
        _fromEngineFd = -1;
        gBridge = self;
    }
    return self;
}

- (BOOL)running { return _running; }

- (NSString *)_enginePath {
    return [[NSBundle mainBundle] pathForResource:@"libgm-engine" ofType:@"dylib"];
}

// 供引擎线程读取我们写入的字节
static int gInFd = -1, gOutFd = -1;

static void *engineThread(void *ctx) {
    (void)ctx;
    NSString *path = gBridge ? [gBridge _enginePath] : nil;
    if (!path) { GMLog(@"dylib 路径为空"); return NULL; }
    void *h = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (!h) {
        GMLog(@"dlopen 失败: %s", dlerror());
        return NULL;
    }
    GMEngineMainFn fn = (GMEngineMainFn)dlsym(h, "gm_engine_main");
    GMSetHostToolFn setter = (GMSetHostToolFn)dlsym(h, "gm_set_host_tool_handler");
    if (setter) {
        setter(GMHostToolDispatch);
        GMLog(@"宿主工具已注册");
    }
    if (!fn) {
        GMLog(@"dlsym gm_engine_main 失败: %s", dlerror());
        return NULL;
    }
    // 告诉引擎 CA 证书位置（iOS 无系统证书路径）
    setenv("GM_BUNDLE_DIR", [NSBundle mainBundle].bundlePath.fileSystemRepresentation, 1);
    NSString *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    NSString *rtDir = [lib stringByAppendingPathComponent:@"Runtimes"];
    [[NSFileManager defaultManager] createDirectoryAtPath:rtDir
                              withIntermediateDirectories:YES attributes:nil error:nil];
    setenv("GM_RUNTIME_DIR", rtDir.fileSystemRepresentation, 1);
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *sessDir = [docs stringByAppendingPathComponent:@"sessions"];
    [[NSFileManager defaultManager] createDirectoryAtPath:sessDir
                              withIntermediateDirectories:YES attributes:nil error:nil];
    setenv("GM_SESSION_DIR", sessDir.fileSystemRepresentation, 1);
    GMLog(@"会话目录: %@", sessDir);
    GMLog(@"运行时目录: %@", rtDir);
    NSString *ca = [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
    if (ca) setenv("GM_CA_FILE", ca.fileSystemRepresentation, 1);
    GMLog(@"CA: %@", ca ?: @"(缺失)");
    // 把 fd 0/1 指向 socketpair 两端
    dup2(gInFd, STDIN_FILENO);
    dup2(gOutFd, STDOUT_FILENO);
    char *argv[] = { "gm-engine", "--mode", "app-server", NULL };
    GMLog(@"engine 线程启动");
    int rc = fn(4, argv);
    GMLog(@"engine 退出 rc=%d", rc);
    return NULL;
}

- (BOOL)startWithError:(NSError **)error {
    if (_running) return YES;
    @synchronized (self) {
        if (_running) return YES;

    NSString *engine = [self _enginePath];
    if (!engine) {
        if (error) {
            *error = [NSError errorWithDomain:@"GMBridge" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"libgm-engine.dylib 未随包发布"}];
        }
        GMLog(@"⚠️ libgm-engine.dylib 不存在");
        return NO;
    }
    GMLog(@"engine dylib: %@", engine);

    // 两条单向管道： App->engine(stdin)，engine->App(stdout)
    int appToEng[2], engToApp[2];
    if (pipe(appToEng) != 0 || pipe(engToApp) != 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"GMBridge" code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"创建管道失败"}];
        }
        return NO;
    }
    _toEngineFd = appToEng[1];      // App 写入
    _fromEngineFd = engToApp[0];    // App 读取
    gInFd = appToEng[0];            // engine 读 stdin
    gOutFd = engToApp[1];           // engine 写 stdout

    _toEngine = [[NSFileHandle alloc] initWithFileDescriptor:_toEngineFd closeOnDealloc:NO];
    _fromEngine = [[NSFileHandle alloc] initWithFileDescriptor:_fromEngineFd closeOnDealloc:NO];

    __weak typeof(self) weakSelf = self;
    [_fromEngine setReadabilityHandler:^(NSFileHandle *h) {
        NSData *chunk = h.availableData;
        if (chunk.length == 0) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            [strongSelf _consume:chunk];
        });
    }];

    pthread_create(&_thread, NULL, engineThread, NULL);
    _running = YES;
    return YES;
    }   /* @synchronized */
}

- (void)stop {
    if (_toEngineFd >= 0) { close(_toEngineFd); _toEngineFd = -1; }
    if (_fromEngineFd >= 0) { close(_fromEngineFd); _fromEngineFd = -1; }
    _running = NO;
}

- (void)_write:(NSDictionary *)message {
    if (_toEngineFd < 0) return;
    NSData *data = [[GMJSONString(message) stringByAppendingString:@"\n"]
                    dataUsingEncoding:NSUTF8StringEncoding];
    const char *bytes = data.bytes;
    size_t left = data.length;
    while (left) {
        ssize_t n = write(_toEngineFd, bytes, left);
        if (n <= 0) break;
        bytes += n; left -= (size_t)n;
    }
}

- (void)call:(NSString *)method params:(id)params reply:(void (^)(id, NSError *))reply {
    long long rid = _nextID++;
    NSMutableDictionary *msg = [NSMutableDictionary dictionary];
    msg[@"jsonrpc"] = @"2.0";
    msg[@"id"] = @(rid);
    msg[@"method"] = method;
    if (params) msg[@"params"] = params;
    if (reply) _pending[@(rid)] = [reply copy];
    [self _write:msg];
}

- (void)notify:(NSString *)method params:(id)params {
    NSMutableDictionary *msg = [NSMutableDictionary dictionary];
    msg[@"jsonrpc"] = @"2.0";
    msg[@"method"] = method;
    if (params) msg[@"params"] = params;
    [self _write:msg];
}

- (void)_consume:(NSData *)chunk {
    [_lineBuffer appendData:chunk];
    const char *bytes = (const char *)_lineBuffer.bytes;
    NSUInteger len = _lineBuffer.length, start = 0;
    for (NSUInteger i = 0; i < len; i++) {
        if (bytes[i] != '\n') continue;
        NSData *line = [NSData dataWithBytes:bytes + start length:i - start];
        start = i + 1;
        if (line.length == 0) continue;
        NSString *text = [[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding];
        id obj = GMJSONParse(text);
        if ([obj isKindOfClass:[NSDictionary class]]) [self _dispatch:obj];
    }
    if (start > 0) [_lineBuffer replaceBytesInRange:NSMakeRange(0, start) withBytes:NULL length:0];
}

- (void)_dispatch:(NSDictionary *)msg {
    id rid = msg[@"id"];
    if (rid && [rid respondsToSelector:@selector(longLongValue)]) {
        void (^cb)(id, NSError *) = _pending[@([rid longLongValue])];
        if (cb) {
            [_pending removeObjectForKey:@([rid longLongValue])];
            id err = msg[@"error"];
            if (err) {
                NSString *m = [err isKindOfClass:[NSDictionary class]] ? err[@"message"] : [err description];
                cb(nil, [NSError errorWithDomain:@"GMEngine" code:-32000
                                        userInfo:@{NSLocalizedDescriptionKey: m ?: @"engine error"}]);
            } else {
                cb(msg[@"result"] ?: [NSNull null], nil);
            }
        }
        return;
    }
    id method = msg[@"method"];
    if ([method isKindOfClass:[NSString class]]) {
        if ([method hasPrefix:@"gm/event/runtime"]) {
            [NSNotificationCenter.defaultCenter postNotificationName:@"gm.runtime"
                                                              object:self
                                                            userInfo:msg[@"params"]];
        }
    }
    if (method) [self.delegate bridge:self didReceiveNotification:msg];
}

- (void)dealloc { [self stop]; }

@end
