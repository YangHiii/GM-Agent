// GM Agent · 会话列表
#import <UIKit/UIKit.h>
#import "GMConversation.h"

@interface GMSessionListViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
- (instancetype)initWithConversation:(GMConversation *)conversation;
@end
