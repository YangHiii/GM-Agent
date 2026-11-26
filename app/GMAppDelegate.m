// GM Agent · AppDelegate + Scene delegate
// 同时兼容两种生命周期：
//   1) iOS 13+ + Info.plist 有 UIApplicationSceneManifest → 走 GMSceneDelegate
//   2) 老式（无 Scene 清单）→ 直接在 didFinishLaunching 建 window
#import "GMAppDelegate.h"
#import "GMLog.h"
#import "GMBridge.h"
#import "GMConversation.h"
#import "GMChatViewController.h"
#import "GMSessionStore.h"
#import "GMDrawerContainer.h"

#pragma mark - 全局状态（AppDelegate 与 SceneDelegate 共享）

@interface GMAppState : NSObject
@property (nonatomic, strong) GMBridge *bridge;
@property (nonatomic, strong) GMConversation *conversation;
@property (nonatomic, strong, readonly) GMConversation *ensureConversation;
+ (instancetype)shared;
@end

@implementation GMAppState
+ (instancetype)shared {
    static GMAppState *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [GMAppState new]; });
    return s;
}
- (GMBridge *)bridge {
    if (!_bridge) {
        _bridge = [GMBridge shared];
        NSError *err = nil;
        if (![_bridge startWithError:&err]) {
            GMLog(@"引擎启动失败: %@", err.localizedDescription);
        }
    }
    return _bridge;
}
- (GMConversation *)conversation {
    if (!_conversation) {
        _conversation = [[GMConversation alloc] initWithBridge:self.bridge];
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        NSString *m = [d stringForKey:@"gm.model"];
        NSString *e = [d stringForKey:@"gm.effort"];
        if (m.length) _conversation.model = m;
        if (e.length) _conversation.effort = e;
    }
    return _conversation;
}
- (GMConversation *)ensureConversation { return self.conversation; }
@end

#pragma mark - 根控制器构造

static UIViewController *GMGLMakeRoot(void) {
    GMLog(@"building root view controller");
    @try {
        GMChatViewController *chat = [[GMChatViewController alloc]
                                      initWithConversation:GMAppState.shared.conversation];
        NSString *last = [GMSessionStore shared].currentThreadID;
        if (last.length) {
            GMLog(@"恢复会话 %@", last);
            [GMAppState.shared.conversation loadThread:last];
        }
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:chat];
        nav.navigationBar.prefersLargeTitles = NO;

        GMSidebarViewController *sidebar = [GMSidebarViewController new];
        sidebar.conversation = GMAppState.shared.conversation;

        GMDrawerContainer *drawer = [[GMDrawerContainer alloc] initWithContent:nav sidebar:sidebar];
        GMLog(@"root VC ready: drawer");
        return drawer;
    } @catch (NSException *e) {
        GMLog(@"根视图构造失败: %@ %@", e.name, e.reason);
        return [GMSplashViewController new];
    }
}

#pragma mark - AppDelegate

@interface GMAppDelegate ()
@property (nonatomic, strong) UIWindow *gmWindow;   // 避免与 UIApplicationDelegate.window 冲突
@end

@implementation GMAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    GMLog(@"didFinishLaunching, scenes=%lu, manifest=%@", (unsigned long)application.connectedScenes.count, [NSBundle.mainBundle objectForInfoDictionaryKey:@"UIApplicationSceneManifest"] ? @"YES" : @"NO");

    BOOL usesScenes = application.supportsMultipleScenes;
    NSDictionary *manifest = [NSBundle.mainBundle objectForInfoDictionaryKey:@"UIApplicationSceneManifest"];

    if (!manifest) {
        GMLog(@"no scene manifest -> legacy window path");
        // 老式：直接建 window
        self.gmWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        self.gmWindow.rootViewController = GMGLMakeRoot();
        [self.gmWindow makeKeyAndVisible];
    }
    (void)usesScenes;
    return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application
configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                              options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *cfg = [[UISceneConfiguration alloc] initWithName:@"Default"
                                                              sessionRole:connectingSceneSession.role];
    cfg.delegateClass = NSClassFromString(@"GMSceneDelegate");
    return cfg;
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    [GMAppState.shared.conversation cancelCurrentTurn];
}

@end

#pragma mark - SceneDelegate

@interface GMSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation GMSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    GMLog(@"scene willConnectToSession");
    UIWindowScene *ws = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:ws];
    self.window.frame = ws.coordinateSpace.bounds;
    self.window.rootViewController = GMGLMakeRoot();
    GMLog(@"window makeKeyAndVisible, root=%@", self.window.rootViewController);
    [self.window makeKeyAndVisible];
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    [self.window makeKeyAndVisible];
}

@end

#pragma mark - 启动占位页（万一根视图构造失败也不至于纯黑）

@implementation GMSplashViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    UILabel *l = [UILabel new];
    l.text = @"GM Agent\n正在启动…";
    l.numberOfLines = 0;
    l.textAlignment = NSTextAlignmentCenter;
    l.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
    l.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:l];
    [NSLayoutConstraint activateConstraints:@[
        [l.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [l.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
}
@end
