// GM Agent · 环形进度（上下文用量 / 存储占用）
#import <UIKit/UIKit.h>

@interface GMRingView : UIView
@property (nonatomic) CGFloat progress;      // 0...1
@property (nonatomic, copy) NSString *centerText;
@property (nonatomic, strong) UIColor *ringColor;
@property (nonatomic) CGFloat lineWidth;
- (void)setProgress:(CGFloat)p animated:(BOOL)animated;
@end
