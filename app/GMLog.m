// GM Agent · 启动日志：写到 Documents/boot.log（UIFileSharingEnabled=YES，可直接在文件 App 里看）
#import "GMLog.h"
#include <stdio.h>
#include <time.h>

NSString *GMLogPath(void) {
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    if (!dir.length) dir = NSTemporaryDirectory();
    return [dir stringByAppendingPathComponent:@"boot.log"];
}

NSString *GMLogEnginePath(void) {
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    if (!dir.length) dir = NSTemporaryDirectory();
    return [dir stringByAppendingPathComponent:@"engine.log"];
}

void GMLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);

    time_t t = time(NULL);
    struct tm tmv;
    localtime_r(&t, &tmv);
    char tsbuf[32];
    strftime(tsbuf, sizeof(tsbuf), "%H:%M:%S", &tmv);
    NSString *ts = [NSString stringWithUTF8String:tsbuf];

    fprintf(stderr, "[GM %s] %s\n", tsbuf, msg.UTF8String);

    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("gm.log", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_async(q, ^{
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", ts, msg];
        NSArray *paths = @[GMLogPath(),
                           @"/var/mobile/Documents/gm-agent.log",
                           @"/var/mobile/gm-agent.log"];
        for (NSString *path in paths) {
            FILE *f = fopen(path.UTF8String, "a");
            if (!f) continue;
            fputs(line.UTF8String, f);
            fclose(f);
        }
    });
}
