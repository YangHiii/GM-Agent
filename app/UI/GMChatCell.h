// GM Agent · 聊天 cell（MT 风格：用户蓝气泡 + AI 无气泡 + 折叠工具卡）
#import <UIKit/UIKit.h>
#import "GMMessage.h"

@class GMChatCell;

typedef void (^GMChatCellAction)(GMChatCell *cell);

@interface GMChatCell : UITableViewCell

@property (nonatomic, strong) UITextView *bodyView;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UIButton *codeCopyButton;
@property (nonatomic, strong) UIView *bubble;
@property (nonatomic, strong) UIView *toolCard;
@property (nonatomic, strong) UILabel *toolTitleLabel;
@property (nonatomic, strong) UILabel *toolPreviewLabel;
@property (nonatomic, strong) UILabel *toolChevron;

@property (nonatomic, copy) GMChatCellAction onCopy;
@property (nonatomic, copy) GMChatCellAction onToggleTool;
@property (nonatomic, copy) GMChatCellAction onToggleReasoning;

/// 根据消息配置外观；返回 cell（便于链式）
- (void)configureWithMessage:(GMMessage *)m
                       index:(NSInteger)index
                     onCopy:(GMChatCellAction)onCopy
                onToggleTool:(GMChatCellAction)onToggleTool
           onToggleReasoning:(GMChatCellAction)onToggleReasoning;

/// 供控制器计算高度时使用
+ (CGFloat)heightForMessage:(GMMessage *)m width:(CGFloat)width;

@end
