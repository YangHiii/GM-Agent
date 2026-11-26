// GM Agent · 聊天 cell 实现
#import "GMChatCell.h"
#import "GMMarkdown.h"

static UIColor *GMUserBubbleColor(void) {
    return [UIColor colorWithRed:0.16 green:0.45 blue:0.98 alpha:1.0];
}

@interface GMChatCell ()
@property (nonatomic, copy) GMChatCellAction onCopyCb;
@property (nonatomic, copy) GMChatCellAction onToggleToolCb;
@property (nonatomic, copy) GMChatCellAction onToggleReasoningCb;
@property (nonatomic, strong) UITapGestureRecognizer *toolTap;
@property (nonatomic, strong) UITapGestureRecognizer *reasoningTap;
@property (nonatomic, strong) NSMutableArray<NSLayoutConstraint *> *activeConstraints;
@end

@implementation GMChatCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.contentView.backgroundColor = UIColor.clearColor;

        /* 气泡背景（仅用户消息显示；AI 消息无气泡以贴近 MT） */
        _bubble = [UIView new];
        _bubble.translatesAutoresizingMaskIntoConstraints = NO;
        _bubble.layer.cornerRadius = 18;
        _bubble.layer.cornerCurve = kCACornerCurveContinuous;
        _bubble.backgroundColor = GMUserBubbleColor();
        _bubble.hidden = YES;
        [self.contentView addSubview:_bubble];

        _metaLabel = [UILabel new];
        _metaLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        _metaLabel.textColor = UIColor.tertiaryLabelColor;
        _metaLabel.numberOfLines = 1;
        _metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_metaLabel];

        _bodyView = [UITextView new];
        _bodyView.editable = NO;
        _bodyView.scrollEnabled = NO;
        _bodyView.selectable = YES;
        _bodyView.backgroundColor = UIColor.clearColor;
        _bodyView.textContainerInset = UIEdgeInsetsZero;
        _bodyView.textContainer.lineFragmentPadding = 0;
        _bodyView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_bodyView];

        /* 工具折叠卡片 */
        _toolCard = [UIView new];
        _toolCard.translatesAutoresizingMaskIntoConstraints = NO;
        _toolCard.backgroundColor = [UIColor secondarySystemBackgroundColor];
        _toolCard.layer.cornerRadius = 12;
        _toolCard.layer.cornerCurve = kCACornerCurveContinuous;
        _toolCard.hidden = YES;
        [self.contentView addSubview:_toolCard];

        _toolTitleLabel = [UILabel new];
        _toolTitleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
        _toolTitleLabel.textColor = UIColor.secondaryLabelColor;
        _toolTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_toolCard addSubview:_toolTitleLabel];

        _toolPreviewLabel = [UILabel new];
        _toolPreviewLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
        _toolPreviewLabel.textColor = UIColor.tertiaryLabelColor;
        _toolPreviewLabel.numberOfLines = 1;
        _toolPreviewLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _toolPreviewLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_toolCard addSubview:_toolPreviewLabel];

        _toolChevron = [UILabel new];
        _toolChevron.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
        _toolChevron.textColor = UIColor.tertiaryLabelColor;
        _toolChevron.text = @"▸";
        _toolChevron.translatesAutoresizingMaskIntoConstraints = NO;
        [_toolCard addSubview:_toolChevron];

        _codeCopyButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _codeCopyButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_codeCopyButton setTitle:@"复制代码" forState:UIControlStateNormal];
        _codeCopyButton.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        _codeCopyButton.backgroundColor = UIColor.tertiarySystemFillColor;
        _codeCopyButton.layer.cornerRadius = 6;
        _codeCopyButton.contentEdgeInsets = UIEdgeInsetsMake(2, 8, 2, 8);
        _codeCopyButton.hidden = YES;
        [_codeCopyButton addTarget:self action:@selector(copyTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_codeCopyButton];

        _toolTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toolTapped)];
        [_toolCard addGestureRecognizer:_toolTap];
    }
    return self;
}

- (void)copyTapped { if (self.onCopyCb) self.onCopyCb(self); }
- (void)toolTapped { if (self.onToggleToolCb) self.onToggleToolCb(self); }

#pragma mark - 布局

- (void)configureWithMessage:(GMMessage *)m
                       index:(NSInteger)index
                     onCopy:(GMChatCellAction)onCopy
                onToggleTool:(GMChatCellAction)onToggleTool
           onToggleReasoning:(GMChatCellAction)onToggleReasoning {
    self.onCopyCb = onCopy;
    self.onToggleToolCb = onToggleTool;
    self.onToggleReasoningCb = onToggleReasoning;

    if (self.activeConstraints.count) {
        [NSLayoutConstraint deactivateConstraints:self.activeConstraints];
        [self.activeConstraints removeAllObjects];
    }

    BOOL isUser = (m.role == GMRoleUser);
    BOOL isTool = (m.role == GMRoleTool);
    BOOL isSystem = (m.role == GMRoleSystem);

    self.bubble.hidden = !isUser;
    self.toolCard.hidden = !isTool;
    self.bodyView.hidden = isTool;
    self.metaLabel.hidden = NO;

    UIView *leadingAnchorView = self.contentView;
    NSLayoutXAxisAnchor *bodyLeading = self.contentView.leadingAnchor;
    NSLayoutXAxisAnchor *bodyTrailing = self.contentView.trailingAnchor;
    CGFloat leadPad = 16, trailPad = 16;

    if (isUser) {
        leadPad = 60;                 /* 右对齐气泡：左侧留白 */
        trailPad = 16;
        self.metaLabel.textAlignment = NSTextAlignmentRight;
        self.metaLabel.text = @"你";
    } else if (isTool) {
        leadPad = 16;
        trailPad = 16;
    } else if (isSystem) {
        leadPad = 16;
        trailPad = 16;
    } else {
        leadPad = 16;
        trailPad = 16;
        self.metaLabel.text = m.streaming ? @"GM Agent · 生成中…" : @"GM Agent";
        self.metaLabel.textAlignment = NSTextAlignmentLeft;
    }

    NSMutableArray<NSLayoutConstraint *> *cs = [NSMutableArray array];

    /* meta 行 */
    [cs addObject:[self.metaLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12]];
    [cs addObject:[self.metaLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor
                                                              constant:isUser ? 60 : 16]];
    [cs addObject:[self.metaLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor
                                                               constant:isUser ? -16 : -16]];

    if (isTool) {
        [cs addObject:[self.toolCard.topAnchor constraintEqualToAnchor:self.metaLabel.bottomAnchor constant:6]];
        [cs addObject:[self.toolCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16]];
        [cs addObject:[self.toolCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16]];

        [cs addObject:[self.toolTitleLabel.topAnchor constraintEqualToAnchor:self.toolCard.topAnchor constant:10]];
        [cs addObject:[self.toolTitleLabel.leadingAnchor constraintEqualToAnchor:self.toolCard.leadingAnchor constant:12]];
        [cs addObject:[self.toolTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.toolChevron.leadingAnchor
                                                                                  constant:-8]];

        [cs addObject:[self.toolChevron.centerYAnchor constraintEqualToAnchor:self.toolTitleLabel.centerYAnchor]];
        [cs addObject:[self.toolChevron.trailingAnchor constraintEqualToAnchor:self.toolCard.trailingAnchor constant:-12]];
        [cs addObject:[self.toolChevron.widthAnchor constraintEqualToConstant:12]];

        [cs addObject:[self.toolPreviewLabel.topAnchor constraintEqualToAnchor:self.toolTitleLabel.bottomAnchor constant:3]];
        [cs addObject:[self.toolPreviewLabel.leadingAnchor constraintEqualToAnchor:self.toolCard.leadingAnchor constant:12]];
        [cs addObject:[self.toolPreviewLabel.trailingAnchor constraintEqualToAnchor:self.toolCard.trailingAnchor constant:-12]];
        [cs addObject:[self.toolPreviewLabel.bottomAnchor constraintEqualToAnchor:self.toolCard.bottomAnchor constant:-10]];

        [cs addObject:[self.contentView.bottomAnchor constraintEqualToAnchor:self.toolCard.bottomAnchor constant:8]];
    } else {
        /* 正文 */
        [cs addObject:[self.bodyView.topAnchor constraintEqualToAnchor:self.metaLabel.bottomAnchor constant:4]];
        [cs addObject:[self.bodyView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:leadPad]];
        [cs addObject:[self.bodyView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-trailPad]];

        if (isUser) {
            /* 气泡包住正文 */
            [cs addObject:[self.bubble.topAnchor constraintEqualToAnchor:self.metaLabel.bottomAnchor constant:-3]];
            [cs addObject:[self.bubble.leadingAnchor constraintEqualToAnchor:self.bodyView.leadingAnchor constant:-12]];
            [cs addObject:[self.bubble.trailingAnchor constraintEqualToAnchor:self.bodyView.trailingAnchor constant:12]];
            [cs addObject:[self.bubble.bottomAnchor constraintEqualToAnchor:self.bodyView.bottomAnchor constant:9]];
        }

        [cs addObject:[self.codeCopyButton.topAnchor constraintEqualToAnchor:self.bodyView.bottomAnchor constant:6]];
        [cs addObject:[self.codeCopyButton.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16]];
        [cs addObject:[self.codeCopyButton.heightAnchor constraintEqualToConstant:24]];

        id bottomRef = self.codeCopyButton.hidden ? self.bodyView : self.codeCopyButton;
        [cs addObject:[self.contentView.bottomAnchor constraintEqualToAnchor:bottomRef constant:10]];
    }

    [NSLayoutConstraint activateConstraints:cs];
    self.activeConstraints = cs;

    /* 内容 */
    if (isTool) {
        self.toolTitleLabel.text = [NSString stringWithFormat:@"工具 · %@", m.toolName ?: @"shell"];
        NSString *body = m.toolSummary ?: @"";
        if (m.toolExpanded) {
            self.toolPreviewLabel.text = body;
            self.toolPreviewLabel.numberOfLines = 0;
            self.toolChevron.text = @"▾";
            self.toolPreviewLabel.font = [UIFont monospacedSystemFontOfSize:10.5
                                                                    weight:UIFontWeightRegular];
        } else {
            NSString *first = [[body componentsSeparatedByCharactersInSet:
                                [NSCharacterSet newlineCharacterSet]] firstObject] ?: @"";
            self.toolPreviewLabel.text = first;
            self.toolPreviewLabel.numberOfLines = 1;
            self.toolChevron.text = @"▸";
        }
    } else {
        NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] init];

        /* 思考过程折叠行 */
        if (m.reasoning.length > 0 && !isUser && !isSystem) {
            NSString *fold = m.reasoningExpanded
                ? [NSString stringWithFormat:@"💭 思考过程（点此收起）\n"]
                : [NSString stringWithFormat:@"💭 思考 %lu 字（点此展开）\n",
                   (unsigned long)m.reasoning.length];
            NSAttributedString *r = [[NSAttributedString alloc] initWithString:fold
                attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:11.5],
                             NSForegroundColorAttributeName: UIColor.tertiaryLabelColor}];
            [attr appendAttributedString:r];
            if (m.reasoningExpanded) {
                NSString *body = [m.reasoning stringByAppendingString:@"\n\n"];
                [attr appendAttributedString:[[NSAttributedString alloc] initWithString:body
                    attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12],
                                 NSForegroundColorAttributeName: UIColor.tertiaryLabelColor}]];
            }
        }

        if (m.text.length) {
            NSAttributedString *rendered = [GMMarkdown render:m.text];
            if (isUser) {
                /* 用户气泡内文字统一白色 */
                NSMutableAttributedString *w = [rendered mutableCopy];
                [w addAttribute:NSForegroundColorAttributeName value:UIColor.whiteColor
                          range:NSMakeRange(0, w.length)];
                [attr appendAttributedString:w];
            } else {
                [attr appendAttributedString:rendered];
            }
        } else if (m.streaming) {
            [attr appendAttributedString:[[NSAttributedString alloc] initWithString:@"…"
                attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:15],
                             NSForegroundColorAttributeName: UIColor.secondaryLabelColor}]];
        }
        self.bodyView.attributedText = attr;

        /* 代码复制 */
        NSArray<NSString *> *codes = [GMMarkdown extractCodeBlocks:m.text ?: @""];
        self.codeCopyButton.hidden = (codes.count == 0);
        if (codes.count) {
            [self.codeCopyButton setTitle:(codes.count == 1 ? @"复制代码" :
                [NSString stringWithFormat:@"复制代码（%lu 段）", (unsigned long)codes.count])
                                 forState:UIControlStateNormal];
        }
    }
}

+ (CGFloat)heightForMessage:(GMMessage *)m width:(CGFloat)width {
    CGFloat contentWidth = width - 32;
    if (m.role == GMRoleUser) contentWidth = width - 76;

    if (m.role == GMRoleTool) {
        NSString *body = m.toolSummary ?: @"";
        CGFloat h = 10 + 18 + 3;
        if (m.toolExpanded) {
            CGRect r = [body boundingRectWithSize:CGSizeMake(contentWidth - 24, CGFLOAT_MAX)
                                          options:NSStringDrawingUsesLineFragmentOrigin
                                       attributes:@{NSFontAttributeName: [UIFont monospacedSystemFontOfSize:10.5]}
                                          context:nil];
            h += r.height;
        } else {
            h += 16;
        }
        return MAX(56, h + 10 + 12 + 6 + 8);
    }

    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] init];
    if (m.reasoning.length > 0 && m.role == GMRoleAssistant) {
        if (m.reasoningExpanded) {
            [attr appendAttributedString:[[NSAttributedString alloc] initWithString:[m.reasoning stringByAppendingString:@"\n\n"]
                attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12]}]];
        } else {
            [attr appendAttributedString:[[NSAttributedString alloc] initWithString:@"x\n" attributes:@{}]];
        }
    }
    [attr appendAttributedString:[GMMarkdown render:m.text ?: @"…"]];
    CGRect r = [attr boundingRectWithSize:CGSizeMake(contentWidth, CGFLOAT_MAX)
                                  options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                  context:nil];
    CGFloat extra = 12 + 16 + 4 + 10;   /* meta + padding */
    if (m.role == GMRoleAssistant && [[GMMarkdown extractCodeBlocks:m.text ?: @""] count] > 0) extra += 30;
    return MAX(44, ceil(r.height) + extra);
}

- (void)prepareForReuse {
    [super prepareForReuse];
    if (self.activeConstraints.count) {
        [NSLayoutConstraint deactivateConstraints:self.activeConstraints];
        [self.activeConstraints removeAllObjects];
    }
    self.onCopyCb = nil;
    self.onToggleToolCb = nil;
    self.onToggleReasoningCb = nil;
}

@end
