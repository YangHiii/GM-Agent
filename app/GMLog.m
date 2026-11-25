// GM Agent · 启动日志：写到 Documents/boot.log（UIFileSharingEnabled=YES，可直接在文件 App 里看）
#import "GMLog.h"
#include <stdio.h>
#include <time.h>

NSString *GMLogPath(void) {
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [dir stringByAppendingPathComponent:@"boot.log"];
}

void GMLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);

    time_t t = time(NULL);
    struct tm tmv;
    localtime_r(&t, &tmv);
    char ts[32];
    strftime(ts, sizeof(ts), "%H:%M:%S", &tmv);

    fprintf(stderr, "[GM %s] %s\n", ts, msg.UTF8String);

    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("gm.log", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_async(q, ^{
        NSString *line = [NSString stringWithFormat:@"%s %@\n", ts, msg];
        NSString *path = GMLogPath();
        FILE *f = fopen(path.UTF8String, "a");
        if (f) {
            fputs(line.UTF8String, f);
            fclose(f);
        }
    });
}
