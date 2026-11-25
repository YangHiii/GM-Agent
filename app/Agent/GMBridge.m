// GM Agent · 引擎桥
// 用 fork/execve + dup2 手动重定向（不依赖 posix_spawn，避免 iOS SDK 的 spawn.h 受限问题）
#import "GMBridge.h"
#import "GMJSON.h"

#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <errno.h>

extern char **environ;

@interface GMBridge () {
    pid_t _pid;
    NSFileHandle *_toEngine;
    NSFileHandle *_fromEngine;
    NSMutableDictionary<NSNumber *, void (^)(id, NSError *)> *_pending;
    long long _nextID;
    NSMutableData *_lineBuffer;
}
@end

@implementation GMBridge

- (instancetype)init {
    if ((self = [super init])) {
        _pending = [NSMutableDictionary dictionary];
        _nextID = 1;
        _lineBuffer = [NSMutableData data];
    }
    return self;
}

- (BOOL)running { return _pid > 0; }

- (NSString *)_enginePath {
    return [[NSBundle mainBundle] pathForResource:@"gm-engine" ofType:nil];
}

- (BOOL)startWithError:(NSError **)error {
    if (self.running) return YES;

    NSString *engine = [self _enginePath];
    if (!engine) {
        if (error) {
            *error = [NSError errorWithDomain:@"GMBridge" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"gm-engine 未随包发布"}];
        }
        return NO;
    }

    // 三条管道：stdin / stdout / stderr
    int inFds[2], outFds[2], errFds[2];
    if (pipe(inFds) != 0 || pipe(outFds) != 0 || pipe(errFds) != 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"GMBridge" code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"创建管道失败"}];
        }
        return NO;
    }

    const char *path = engine.fileSystemRepresentation;
    pid_t pid = fork();
    if (pid < 0) {
        close(inFds[0]); close(inFds[1]);
        close(outFds[0]); close(outFds[1]);
        close(errFds[0]); close(errFds[1]);
        if (error) {
            *error = [NSError errorWithDomain:@"GMBridge" code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"fork 失败"}];
        }
        return NO;
    }

    if (pid == 0) {
        // ---- 子进程 ----
        dup2(inFds[0], STDIN_FILENO);
        dup2(outFds[1], STDOUT_FILENO);
        dup2(errFds[1], STDERR_FILENO);
        close(inFds[0]); close(inFds[1]);
        close(outFds[0]); close(outFds[1]);
        close(errFds[0]); close(errFds[1]);

        char *const argv[] = { (char *)path, "--mode", "app-server", NULL };
        execve(path, argv, environ);
        _exit(127);   // exec 失败
    }

    // ---- 父进程 ----
    close(inFds[0]);
    close(outFds[1]);
    close(errFds[1]);

    _pid = pid;
    _toEngine = [[NSFileHandle alloc] initWithFileDescriptor:inFds[1] closeOnDealloc:YES];
    _fromEngine = [[NSFileHandle alloc] initWithFileDescriptor:outFds[0] closeOnDealloc:YES];
    NSFileHandle *errHandle = [[NSFileHandle alloc] initWithFileDescriptor:errFds[0] closeOnDealloc:YES];

    __weak typeof(self) weakSelf = self;
    [_fromEngine setReadabilityHandler:^(NSFileHandle *h) {
        NSData *chunk = h.availableData;
        if (chunk.length == 0) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            [strongSelf _consume:chunk];
        });
    }];
    [errHandle setReadabilityHandler:^(NSFileHandle *h) {
        NSData *chunk = h.availableData;
        if (chunk.length == 0) return;
        NSString *line = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding];
        NSLog(@"[gm-engine] %@", line);
    }];

    dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)pid,
                                                   DISPATCH_PROC_EXIT, dispatch_get_main_queue());
    if (src) {
        dispatch_source_set_event_handler(src, ^{
            dispatch_source_cancel(src);
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf->_pid = 0;
            [strongSelf.delegate bridge:strongSelf didExitWithStatus:0];
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
    @try { [_toEngine writeData:data]; } @catch (__unused NSException *e) { }
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
    if (method) [self.delegate bridge:self didReceiveNotification:msg];
}

- (void)dealloc { [self stop]; }

@end
