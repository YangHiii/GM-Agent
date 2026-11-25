// GM Agent · 引擎桥实现：posix_spawn + NSPipe 行分隔 JSON-RPC
#import "GMBridge.h"
#import "GMJSON.h"

@interface GMBridge () {
    pid_t _pid;
    NSFileHandle *_toEngine;
    NSFileHandle *_fromEngine;
    NSMutableDictionary<NSNumber *, void (^)(id, NSError *)> *_pending;
    long long _nextID;
    dispatch_queue_t _ioQueue;
    NSMutableData *_lineBuffer;
}
@end

@implementation GMBridge

- (instancetype)init {
    if ((self = [super init])) {
        _pending = [NSMutableDictionary dictionary];
        _nextID = 1;
        _ioQueue = dispatch_queue_create("app.gm.agent.bridge.io", DISPATCH_QUEUE_SERIAL);
        _lineBuffer = [NSMutableData data];
    }
    return self;
}

- (BOOL)running {
    return _pid > 0;
}

- (NSString *)_enginePath {
    return [[NSBundle mainBundle] pathForResource:@"gm-engine" ofType:nil];
}

- (BOOL)startWithError:(NSError **)error {
    if (self.running) return YES;
    NSString *engine = [self _enginePath];
    if (!engine) {
        if (error) *error = [NSError errorWithDomain:@"GMBridge" code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"gm-engine 未随包发布"}];
        return NO;
    }

    NSPipe *inPipe = [NSPipe pipe];   // app -> engine
    NSPipe *outPipe = [NSPipe pipe];  // engine -> app
    NSPipe *errPipe = [NSPipe pipe];  // engine stderr (日志)

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, inPipe.fileHandleForReading.fileDescriptor, STDIN_FILENO);
    posix_spawn_file_actions_adddup2(&actions, outPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, errPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO);

    const char *argv[] = { engine.fileSystemRepresentation, "--mode", "app-server", NULL };
    // 引擎需要完整环境（PATH/HOME 供工具执行）
    extern char **environ;
    pid_t pid = 0;
    int rc = posix_spawn(&pid, engine.fileSystemRepresentation, &actions, NULL,
                         (char *const *)argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    if (rc != 0) {
        if (error) *error = [NSError errorWithDomain:@"GMBridge" code:2
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                       [NSString stringWithFormat:@"拉起引擎失败: %s", strerror(rc)]}];
        return NO;
    }
    _pid = pid;
    _toEngine = inPipe.fileHandleForWriting;
    _fromEngine = outPipe.fileHandleForReading;

    __weak typeof(self) weakSelf = self;
    [_fromEngine setReadabilityHandler:^(NSFileHandle *h) {
        NSData *chunk = h.availableData;
        if (chunk.length == 0) return;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf _consume:chunk]; });
    }];
    [errPipe.fileHandleForReading setReadabilityHandler:^(NSFileHandle *h) {
        NSData *chunk = h.availableData;
        if (chunk.length == 0) return;
        NSString *line = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding];
        NSLog(@"[gm-engine] %@", line);
    }];

    dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)pid,
                                                   DISPATCH_PROC_EXIT,
                                                   dispatch_get_main_queue());
    if (src) {
        dispatch_source_set_event_handler(src, ^{
            dispatch_source_cancel(src);
            weakSelf->_pid = 0;
            [weakSelf.delegate bridge:weakSelf didExitWithStatus:0];
        });
        dispatch_resume(src);
    }
    return YES;
}

- (void)stop {
    if (_toEngine) {
        @try { [_toEngine closeFile]; } @catch (__unused NSException *e) {}
        _toEngine = nil;
    }
    if (_pid > 0) {
        kill(_pid, SIGTERM);
        _pid = 0;
    }
}

- (void)_write:(NSDictionary *)message {
    if (!_toEngine) return;
    NSData *data = [[GMJSONString(message) stringByAppendingString:@"\n"]
                    dataUsingEncoding:NSUTF8StringEncoding];
    @try { [_toEngine writeData:data]; } @catch (__unused NSException *e) { /* 引擎已退 */ }
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
    const char *bytes = _lineBuffer.bytes;
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
    if (method) [self.delegate bridge:self didReceiveNotification:msg];
}

- (void)dealloc {
    [self stop];
}
@end
