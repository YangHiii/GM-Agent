// GM Agent · 抽屉容器：左侧滑出侧边栏（对齐 MT 的 drawer 交互）
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class GMConversation;

/// 侧边栏（会话 + 项目 + 用量卡）
@interface GMSidebarViewController : UIViewController

@property (nonatomic, strong) GMConversation *conversation;
/// 选中某个会话后回调（抽屉会关闭）
@property (nonatomic, copy) void (^onSelectSession)(NSString *threadID);
/// 点击"新对话"
@property (nonatomic, copy) void (^onNewSession)(void);
/// 点击供应商行
@property (nonatomic, copy) void (^onOpenSettings)(void);

- (void)reload;
@end

/// 抽屉容器：包住主内容，支持右滑打开侧边栏
@interface GMDrawerContainer : UIViewController
- (instancetype)initWithContent:(UIViewController *)content
                        sidebar:(GMSidebarViewController *)sidebar;
- (void)openDrawerAnimated:(BOOL)animated;
- (void)closeDrawerAnimated:(BOOL)animated;
@property (nonatomic, readonly) BOOL isDrawerOpen;
@end

NS_ASSUME_NONNULL_END
