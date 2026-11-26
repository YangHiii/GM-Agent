// GM Agent · 设置主页面（按 MT Agent 分组结构）
#import <UIKit/UIKit.h>
#import "GMConversation.h"

@interface GMSettingsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
- (instancetype)initWithConversation:(GMConversation *)conversation;
@end
