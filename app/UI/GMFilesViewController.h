// GM Agent · 文件浏览
#import <UIKit/UIKit.h>

@property (nonatomic, copy) NSString *startPath;

@interface GMFilesViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
- (instancetype)initWithPath:(NSString *)path;
/// 目录选择模式：右上显示"选择"，点后回调
- (instancetype)initAsPicker:(void (^)(NSString *path))onPick;
@end
