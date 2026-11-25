// GM Agent · 聊天主界面
#import <UIKit/UIKit.h>
#import "GMConversation.h"

@interface GMChatViewController : UIViewController
- (instancetype)initWithConversation:(GMConversation *)conversation;
@end
