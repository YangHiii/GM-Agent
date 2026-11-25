// GM Agent · AppDelegate
#import "GMAppDelegate.h"
#import "GMBridge.h"
#import "GMConversation.h"
#import "GMChatViewController.h"

@interface GMAppDelegate ()
@property (nonatomic, strong) GMBridge *bridge;
@property (nonatomic, strong) GMConversation *conversation;
// 注：window 属性已由 UIApplicationDelegate 协议声明，这里不再重复声明
@end

@implementation GMAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.bridge = [GMBridge new];
    NSError *err = nil;
    if (![self.bridge startWithError:&err]) {
        NSLog(@"[GM] 引擎启动失败: %@", err.localizedDescription);
    }
    self.conversation = [[GMConversation alloc] initWithBridge:self.bridge];

    GMChatViewController *chat = [[GMChatViewController alloc] initWithConversation:self.conversation];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:chat];
    nav.navigationBar.prefersLargeTitles = NO;

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    [self.conversation cancelCurrentTurn];
}

@end
