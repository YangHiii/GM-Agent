// GM Agent · 文件浏览
#import <UIKit/UIKit.h>

@interface GMFilesViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
- (instancetype)initWithPath:(NSString *)path;
@end
