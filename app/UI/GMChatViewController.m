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
#import "GMChatCell.h"

@interface GMChatViewController () <UITableViewDataSource, UITableViewDelegate, UITextViewDelegate, GMConversationDelegate>
@property (nonatomic, strong) GMConversation *conversation;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UITextView *input;
@property (nonatomic, strong) UIButton *sendButton;
@property (nonatomic, strong) UIView *composer;
@property (nonatomic, strong) NSLayoutConstraint *composerBottom;
@property (nonatomic) BOOL generating;
@property (nonatomic, strong) GMRingView *contextRing;
@property (nonatomic, strong) NSMutableArray<NSString *> *pendingQueue;
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
    self.pendingQueue = [NSMutableArray array];
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
    _table.rowHeight = 44;
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
    NSString *text = [self.input.text stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!text.length) return;
    self.input.text = @"";

    /* 生成中 → 排队，不打断当前回合 */
    if (self.generating) {
        [self.pendingQueue addObject:text];
        UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [h impactOccurred];
        [self updateSendButton];
        return;
    }

    [self.input resignFirstResponder];
    [self.conversation sendUserText:text];
}

- (void)flushPendingQueue {
    if (self.generating || self.pendingQueue.count == 0) return;
    NSString *next = self.pendingQueue.firstObject;
    [self.pendingQueue removeObjectAtIndex:0];
    [self.conversation sendUserText:next];
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
    NSString *sym;
    if (self.generating) {
        sym = self.pendingQueue.count ? @"arrow.up.circle.fill" : @"stop.circle.fill";
        self.sendButton.tintColor = self.pendingQueue.count ? UIColor.systemBlueColor : UIColor.systemRedColor;
    } else {
        sym = @"arrow.up.circle.fill";
        self.sendButton.tintColor = UIColor.labelColor;
    }
    [self.sendButton setImage:[UIImage systemImageNamed:sym] forState:UIControlStateNormal];
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
    BOOL wasGenerating = self.generating;
    self.generating = last.streaming;
    if (wasGenerating && !self.generating) {
        /* 回合结束：延迟一点再发下一条，避免 UI 抖动 */
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self flushPendingQueue]; });
    }
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
    if (indexPath.row >= list.count) return cell;

    GMMessage *m = list[indexPath.row];
    __weak typeof(self) w = self;
    [cell configureWithMessage:m
                         index:indexPath.row
                        onCopy:^(GMChatCell *c) {
        NSArray<NSString *> *codes = [GMMarkdown extractCodeBlocks:m.text ?: @""];
        if (codes.count) {
            [UIPasteboard generalPasteboard].string =
                [codes componentsJoinedByString:@"\n\n"];
            UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc]
                                            initWithStyle:UIImpactFeedbackStyleLight];
            [h impactOccurred];
        }
    }
                  onToggleTool:^(GMChatCell *c) {
        m.toolExpanded = !m.toolExpanded;
        [w.table reloadRowsAtIndexPaths:@[indexPath]
                       withRowAnimation:UITableViewRowAnimationFade];
    }
             onToggleReasoning:^(GMChatCell *c) {
        m.reasoningExpanded = !m.reasoningExpanded;
        [w.table reloadRowsAtIndexPaths:@[indexPath]
                       withRowAnimation:UITableViewRowAnimationFade];
    }];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<GMMessage *> *list = self.conversation.messages;
    if (indexPath.row >= list.count) return 44;
    return [GMChatCell heightForMessage:list[indexPath.row] width:tableView.bounds.size.width];
}

@end
