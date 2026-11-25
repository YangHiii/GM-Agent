// GM Agent · 主入口
#import <UIKit/UIKit.h>
#import "GMAppDelegate.h"
#import "GMLog.h"

int main(int argc, char *argv[]) {
    // 最先写一行：如果连这行都没有，说明进程根本没起来（签名问题）
    GMLog(@"==== main() entered, argv0=%s ====", argv[0]);
    @autoreleasepool {
        int rc = UIApplicationMain(argc, argv, nil, NSStringFromClass([GMAppDelegate class]));
        GMLog(@"==== UIApplicationMain returned %d ====", rc);
        return rc;
    }
}
