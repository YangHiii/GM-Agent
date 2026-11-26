// GM Agent · 轻量 Markdown 渲染（代码块 / 行内代码 / 粗体 / 标题 / 列表 / 表格）
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface GMMarkdown : NSObject
/// 把 Markdown 文本转 NSAttributedString（适配深/浅色）
+ (NSAttributedString *)render:(NSString *)markdown;
/// 提取所有 ``` 代码块内容（用于"复制代码"）
+ (NSArray<NSString *> *)extractCodeBlocks:(NSString *)markdown;
@end

NS_ASSUME_NONNULL_END
