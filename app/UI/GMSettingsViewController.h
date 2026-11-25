// GM Agent · 设置页
// 流程：填网关地址 -> 自动拉取 /models -> 下拉选模型 -> 填 Key -> 测试 -> 保存
#import <UIKit/UIKit.h>
#import "GMConversation.h"

@interface GMSettingsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UITableView *tableView;
- (instancetype)initWithConversation:(GMConversation *)conversation;
@end
