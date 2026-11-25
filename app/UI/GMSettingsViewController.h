// GM Agent · 设置：模型 / 网关 / 密钥
#import <UIKit/UIKit.h>
#import "GMConversation.h"

@interface GMSettingsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITextField *urlField;
@property (nonatomic, strong) UITextField *modelField;
@property (nonatomic, strong) UITextField *keyField;
- (instancetype)initWithConversation:(GMConversation *)conversation;
@end
