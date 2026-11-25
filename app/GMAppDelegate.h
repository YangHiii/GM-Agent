// GM Agent · AppDelegate（UIScene 生命周期）
// iOS 13+ 只要 Info.plist 声明 UIApplicationSceneManifest，就必须实现场景配置，
// 否则 UIApplicationMain 会创建不挂 window 的 delegate → 黑屏。这里显式声明连接代理。
#import <UIKit/UIKit.h>

@interface GMAppDelegate : UIResponder <UIApplicationDelegate>
@end

@interface GMSplashViewController : UIViewController
@end
