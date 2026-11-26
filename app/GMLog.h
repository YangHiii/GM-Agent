// GM Agent · 启动日志（写文件，黑屏时也能取证）
#import <Foundation/Foundation.h>

void GMLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
NSString *GMLogPath(void);
NSString *GMLogEnginePath(void);
