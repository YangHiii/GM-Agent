// GM Agent · 供应商列表（对齐 MT 的 CAThirdPartyProviderListViewController）
#import <UIKit/UIKit.h>
#import "GMConversation.h"

@interface GMProviderListViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
- (instancetype)initWithConversation:(GMConversation *)conversation;
@end
