// GM Agent · 聊天主界面：UITableView + 输入栏，流式渲染
#import "GMChatViewController.h"
#import "GMMessage.h"
#import "GMSettingsViewController.h"
#import "GMDevViewController.h"
#import "GMSessionListViewController.h"
#import "GMSessionStore.h"
#import "GMMarkdown.h"
#import "GMRingView.h"
#import "GMUsageViewController.h"

@interface GMChatCell : UITableViewCell
@property (nonatomic, strong) UITextView *bodyView;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UIButton *copyButton;
@property (nonatomic, copy) void (^onCopy)(void);
@end

@implementation GMChatCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _bodyView = [UITextView new];
        _bodyView.editable = NO;
        _bodyView.scrollEnabled = NO;
        _bodyView.selectable = YES;
        _bodyView.backgroundColor = UIColor.clearColor;
        _bodyView.textContainerInset = UIEdgeInsetsZero;
        _bodyView.textContainer.lineFragmentPadding = 0;
        _bodyView.translatesAutoresizingMaskIntoConstraints = NO;
        _metaLabel = [UILabel new];
        _metaLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
        _metaLabel.textColor = UIColor.secondaryLabelColor;
        _metaLabel.numberOfLines = 0;
        _metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_metaLabel];
        [self.contentView addSubview:_bodyView];

        _copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _copyButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_copyButton setTitle:@"复制代码" forState:UIControlStateNormal];
        _copyButton.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        _copyButton.backgroundColor = UIColor.tertiarySystemFillColor;
        _copyButton.layer.cornerRadius = 6;
        _copyButton.contentEdgeInsets = UIEdgeInsetsMake(2, 8, 2, 8);
        _copyButton.hidden = YES;
        [_copyButton addTarget:self action:@selector(copyTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_copyButton];
        [NSLayoutConstraint activateConstraints:@[
            [_metaLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
            [_metaLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_metaLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_bodyView.topAnchor constraintEqualToAnchor:_metaLabel.bottomAnchor constant:4],
            [_bodyView.leadingAnchor constraintEqualToAnchor:_metaLabel.leadingAnchor],
            [_bodyView.trailingAnchor constraintEqualToAnchor:_metaLabel.trailingAnchor],
            [_copyButton.leadingAnchor constraintEqualToAnchor:_bodyView.leadingAnchor],
            [_copyButton.topAnchor constraintEqualToAnchor:_bodyView.bottomAnchor constant:6],
            [_copyButton.heightAnchor constraintEqualToConstant:24],
            [_copyButton.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
        ]];
    }
    return self;
}

- (void)copyTapped { if (self.onCopy) self.onCopy(); }

- (void)layoutSubviews {
    [super layoutSubviews];
}

@end

@interface GMChatViewController () <UITableViewDataSource, UITableViewDelegate, UITextViewDelegate, GMConversationDelegate>
@property (nonatomic, strong) GMConversation *conversation;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UITextView *input;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIView *composer;
@property (nonatomic, strong) NSLayoutConstraint *composerBottom;
@property (nonatomic) BOOL generating;
@property (nonatomic, strong) GMRingView *contextRing;
@property (nonatomic) NSTimeInterval lastReload;
@property (nonatomic) NSInteger lastCount;
@end

@implementation GMChatViewController

- (instancetype)initWithConversation:(GMConversation *)conversation {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _conversation = conversation;
        _conversation.delegate = self;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [[NSUserDefaults standardUserDefaults] stringForKey:@"gm.agentName"] ?: @"GM Agent";

    /* 副标题显示累计 token */
    UILabel *sub = [UILabel new];
    sub.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
    sub.textColor = UIColor.secondaryLabelColor;
    sub.textAlignment = NSTextAlignmentCenter;
    sub.tag = 777;
    self.navigationItem.titleView = ({
        UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 200, 36)];
        UILabel *main = [UILabel new];
        main.text = self.title;
        main.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        main.textAlignment = NSTextAlignmentCenter;
        main.frame = CGRectMake(0, 0, 200, 22);
        sub.frame = CGRectMake(0, 20, 200, 12);
        [box addSubview:main];
        [box addSubview:sub];
        box;
    });
    [self setupContextRing];
    [self updateTokenLabel];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal"]
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(toggleSidebar)];
    [NSNotificationCenter.defaultCenter addObserver:self
                                          selector:@selector(openSettings)
                                              name:@"gm.openSettings" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                          selector:@selector(openUsagePage)
                                              name:@"gm.openUsage" object:nil];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"]
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(openSettings)];

    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.translatesAutoresizingMaskIntoConstraints = NO;
    _table.dataSource = self;
    _table.delegate = self;
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.rowHeight = UITableViewAutomaticDimension;
    _table.estimatedRowHeight = 72;
    _table.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [_table registerClass:[GMChatCell class] forCellReuseIdentifier:@"cell"];
    [self.view addSubview:_table];

    _composer = [UIView new];
    _composer.translatesAutoresizingMaskIntoConstraints = NO;
    _composer.backgroundColor = UIColor.secondarySystemBackgroundColor;
    _composer.layer.cornerRadius = 18;
    [self.view addSubview:_composer];

    _input = [UITextView new];
    _input.translatesAutoresizingMaskIntoConstraints = NO;
    _input.font = [UIFont systemFontOfSize:15];
    _input.backgroundColor = UIColor.clearColor;
    _input.delegate = self;
    _input.scrollEnabled = NO;
    [_composer addSubview:_input];

    _sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_sendButton setImage:[UIImage systemImageNamed:@"arrow.up.circle.fill"] forState:UIControlStateNormal];
    _sendButton.tintColor = UIColor.labelColor;
    [_sendButton addTarget:self action:@selector(send) forControlEvents:UIControlEventTouchUpInside];
    [_composer addSubview:_sendButton];

    _composerBottom = [_composer.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor
                                                            constant:-8];
    [NSLayoutConstraint activateConstraints:@[
        [_table.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_table.bottomAnchor constraintEqualToAnchor:_composer.topAnchor constant:-6],

        [_composer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12],
        [_composer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12],
        _composerBottom,
        [_composer.heightAnchor constraintGreaterThanOrEqualToConstant:44],

        [_input.leadingAnchor constraintEqualToAnchor:_composer.leadingAnchor constant:12],
        [_input.topAnchor constraintEqualToAnchor:_composer.topAnchor constant:8],
        [_input.bottomAnchor constraintEqualToAnchor:_composer.bottomAnchor constant:-8],
        [_input.trailingAnchor constraintEqualToAnchor:_sendButton.leadingAnchor constant:-6],

        [_sendButton.trailingAnchor constraintEqualToAnchor:_composer.trailingAnchor constant:-10],
        [_sendButton.centerYAnchor constraintEqualToAnchor:_composer.centerYAnchor],
        [_sendButton.widthAnchor constraintEqualToConstant:30],
        [_sendButton.heightAnchor constraintEqualToConstant:30],
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [NSNotificationCenter.defaultCenter addObserver:self
                                          selector:@selector(keyboard:)
                                              name:UIKeyboardWillChangeFrameNotification
                                            object:nil];
}

- (void)keyboard:(NSNotification *)note {
    CGRect end = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat overlap = MAX(0, self.view.bounds.size.height - end.origin.y);
    CGFloat inset = MAX(0, overlap - self.view.safeAreaInsets.bottom);
    self.composerBottom.constant = -8 - inset;
    [UIView animateWithDuration:0.25 animations:^{ [self.view layoutIfNeeded]; }];
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    if ([text isEqualToString:@"\n"] && textView.text.length > 0) {
        [self send];
        return NO;
    }
    return YES;
}

- (void)send {
    if (self.generating) {
        [self.conversation cancelCurrentTurn];
        return;
    }
    NSString *text = self.input.text;
    if (!text.length) return;
    self.input.text = @"";
    [self.input resignFirstResponder];   /* 发送后收起键盘 */
    [self.conversation sendUserText:text];
}

- (void)setupContextRing {
    GMRingView *ring = [[GMRingView alloc] initWithFrame:CGRectMake(0, 0, 26, 26)];
    ring.lineWidth = 2.5;
    ring.progress = 0;
    self.contextRing = ring;
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithCustomView:ring];
    NSMutableArray *items = [self.navigationItem.rightBarButtonItems mutableCopy] ?: [NSMutableArray array];
    [items insertObject:item atIndex:0];
    self.navigationItem.rightBarButtonItems = items;
}

- (void)updateContextRing {
    if (!self.contextRing) return;
    long long in = self.conversation.totalInputTokens;
    long long out = self.conversation.totalOutputTokens;
    long long used = in + out;
    long long window = [self contextWindowForModel];
    if (window <= 0) { self.contextRing.progress = 0; return; }
    CGFloat p = (CGFloat)used / (CGFloat)window;
    self.contextRing.centerText = [NSString stringWithFormat:@"%lldk", (used / 1000)];
    [self.contextRing setProgress:p animated:YES];
}

- (long long)contextWindowForModel {
    NSString *m = [[NSUserDefaults standardUserDefaults] stringForKey:@"gm.model"] ?: @"";
    NSDictionary *table = @{
        @"gpt-5": @400000, @"gpt-5.1": @400000, @"gpt-5.2": @400000,
        @"gpt-5.3-codex": @400000, @"gpt-5.4": @1050000, @"gpt-5.5": @1050000,
        @"gpt-4.1": @1047576, @"gpt-4o": @128000,
        @"deepseek-chat": @64000, @"deepseek-reasoner": @64000,
        @"deepseek-v4-pro": @128000, @"deepseek-flash": @128000,
        @"gemini-2.5-pro": @1048576, @"gemini-2.5-flash": @1048576,
        @"kimi-k2-0905-preview": @256000, @"moonshot-v1-128k": @128000,
        @"glm-4.6": @200000, @"glm-4-plus": @128000,
        @"qwen3-max": @262144, @"qwen-plus": @131072,
    };
    for (NSString *k in table) {
        if ([m hasPrefix:k]) return [table[k] longLongValue];
    }
    return 128000;   /* 兜底 */
}

- (void)updateTokenLabel {
    UILabel *sub = [self.navigationItem.titleView viewWithTag:777];
    if (!sub) return;
    long long in = self.conversation.totalInputTokens;
    long long out = self.conversation.totalOutputTokens;
    if (in + out == 0) { sub.text = @""; return; }
    sub.text = [NSString stringWithFormat:@"↑%lld ↓%lld tokens", in, out];
}

- (void)updateSendButton {
    NSString *sym = self.generating ? @"stop.circle.fill" : @"arrow.up.circle.fill";
    [self.sendButton setImage:[UIImage systemImageNamed:sym] forState:UIControlStateNormal];
    self.sendButton.tintColor = self.generating ? UIColor.systemRedColor : UIColor.labelColor;
}

- (void)newThread {
    [self.conversation newThread];
}

- (void)toggleSidebar {
    [NSNotificationCenter.defaultCenter postNotificationName:@"gm.toggleDrawer" object:nil];
}

- (void)openSessions {
    GMSessionListViewController *v = [[GMSessionListViewController alloc] initWithConversation:self.conversation];
    [self.navigationController pushViewController:v animated:YES];
}

- (void)openUsagePage {
    [self.navigationController pushViewController:[GMUsageViewController new] animated:YES];
}

- (void)openDev {
    [self.navigationController pushViewController:[GMDevViewController new] animated:YES];
}

- (void)openSettings {
    GMSettingsViewController *s = [[GMSettingsViewController alloc] initWithConversation:self.conversation];
    [self.navigationController pushViewController:s animated:YES];
}

#pragma mark - Conversation delegate

- (void)conversationDidChange:(GMConversation *)conversation {
    /* 节流：流式输出时每 80ms 最多刷一次，避免卡顿 */
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - _lastReload < 0.08 && conversation.messages.count == _lastCount) return;
    _lastReload = now;
    _lastCount = conversation.messages.count;

    GMMessage *last = conversation.messages.lastObject;
    self.generating = last.streaming;
    [self updateSendButton];
    [self updateTokenLabel];
    [self updateContextRing];
    [self.table reloadData];
    NSInteger n = [self.table numberOfRowsInSection:0];
    if (n > 0) {
        [self.table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:n - 1 inSection:0]
                          atScrollPosition:UITableViewScrollPositionBottom
                                  animated:YES];
    }
}

- (void)conversation:(GMConversation *)conversation didFail:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"出错"
                                                              message:message
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.conversation.messages.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    GMChatCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    NSArray<GMMessage *> *list = self.conversation.messages;
    if (indexPath.row >= list.count) return cell;   /* 越界保护 */
    GMMessage *m = list[indexPath.row];
    switch (m.role) {
        case GMRoleUser: {
            cell.metaLabel.text = @"你";
            cell.copyButton.hidden = YES;
            cell.onCopy = nil;
            cell.bodyView.attributedText = [[NSAttributedString alloc] initWithString:m.text ?: @""
                attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:15],
                             NSForegroundColorAttributeName: UIColor.labelColor}];
            break;
        }
        case GMRoleTool: {
            cell.metaLabel.text = [NSString stringWithFormat:@"工具 · %@", m.toolName ?: @"tool"];
            NSString *body = m.toolSummary ?: @"";
            cell.bodyView.attributedText = [[NSAttributedString alloc] initWithString:body
                attributes:@{NSFontAttributeName: [UIFont monospacedSystemFontOfSize:11.5
                                                                              weight:UIFontWeightRegular],
                             NSForegroundColorAttributeName: UIColor.tertiaryLabelColor}];
            break;
        }
        case GMRoleSystem: {
            cell.metaLabel.text = @"系统";
            cell.bodyView.attributedText = [[NSAttributedString alloc] initWithString:m.text ?: @""
                attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:13],
                             NSForegroundColorAttributeName: UIColor.secondaryLabelColor}];
            break;
        }
        default: {
            cell.metaLabel.text = m.streaming ? @"GM Agent · 生成中…" : @"GM Agent";
            BOOL simple = [[NSUserDefaults standardUserDefaults] boolForKey:@"gm.simpleDisplay"];
            NSMutableAttributedString *body = [[NSMutableAttributedString alloc] init];

            /* 思考过程：默认折叠为一行 */
            if (m.reasoning.length && !simple) {
                if (m.reasoningExpanded) {
                    NSString *head = @"💭 思考过程（点此收起）\n";
                    [body appendAttributedString:[[NSAttributedString alloc] initWithString:head
                        attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12],
                                     NSForegroundColorAttributeName: UIColor.tertiaryLabelColor}]];
                    [body appendAttributedString:[[NSAttributedString alloc] initWithString:
                        [m.reasoning stringByAppendingString:@"\n────────\n"]
                        attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12],
                                     NSForegroundColorAttributeName: UIColor.tertiaryLabelColor}]];
                } else {
                    NSString *fold = [NSString stringWithFormat:@"💭 思考过程（%lu 字，点此展开）\n\n",
                                      (unsigned long)m.reasoning.length];
                    [body appendAttributedString:[[NSAttributedString alloc] initWithString:fold
                        attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12],
                                     NSForegroundColorAttributeName: UIColor.tertiaryLabelColor}]];
                }
            }

            if (m.text.length) {
                [body appendAttributedString:[GMMarkdown render:m.text]];
            } else if (m.streaming) {
                [body appendAttributedString:[[NSAttributedString alloc] initWithString:@"…"
                    attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:15],
                                 NSForegroundColorAttributeName: UIColor.secondaryLabelColor}]];
            }
            cell.bodyView.attributedText = body;
            /* 有代码块 → 显示"复制代码" */
            NSArray<NSString *> *codes = [GMMarkdown extractCodeBlocks:m.text ?: @""];
            if (codes.count > 0) {
                cell.copyButton.hidden = NO;
                [cell.copyButton setTitle:(codes.count == 1 ? @"复制代码" :
                                          [NSString stringWithFormat:@"复制代码（%lu 段）", (unsigned long)codes.count])
                                 forState:UIControlStateNormal];
                NSArray<NSString *> *copied = codes;
                cell.onCopy = ^{
                    NSString *all = [copied componentsJoinedByString:@"\n\n"];
                    [UIPasteboard generalPasteboard].string = all;
                    UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
                    [h impactOccurred];
                };
            } else {
                cell.copyButton.hidden = YES;
                cell.onCopy = nil;
            }
            break;
        }
    }
    return cell;
}

@end
