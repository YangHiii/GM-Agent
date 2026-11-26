// GM Agent · AI 账号（供应商 / 模型 / Key / 测试）
#import <UIKit/UIKit.h>
#import "GMConversation.h"

@interface GMAIAccountViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UITableView *tableView;
- (instancetype)initWithConversation:(GMConversation *)conversation;
- (instancetype)initWithConversation:(GMConversation *)conversation
                       providerIdent:(NSString *)ident;
@end
