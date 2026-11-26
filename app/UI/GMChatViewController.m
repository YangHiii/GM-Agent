// GM Agent · 聊天主界面：UITableView + 输入栏，流式渲染
#import "GMChatViewController.h"
#import "GMMessage.h"
#import "GMSettingsViewController.h"
#import "GMDevViewController.h"

@interface GMChatCell : UITableViewCell
@property (nonatomic, strong) UILabel *bodyLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@end

@implementation GMChatCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _bodyLabel = [UILabel new];
        _bodyLabel.numberOfLines = 0;
        _bodyLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
        _bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _metaLabel = [UILabel new];
        _metaLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
        _metaLabel.textColor = UIColor.secondaryLabelColor;
        _metaLabel.numberOfLines = 0;
        _metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_metaLabel];
        [self.contentView addSubview:_bodyLabel];
        [NSLayoutConstraint activateConstraints:@[
            [_metaLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
            [_metaLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_metaLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_bodyLabel.topAnchor constraintEqualToAnchor:_metaLabel.bottomAnchor constant:4],
            [_bodyLabel.leadingAnchor constraintEqualToAnchor:_metaLabel.leadingAnchor],
            [_bodyLabel.trailingAnchor constraintEqualToAnchor:_metaLabel.trailingAnchor],
            [_bodyLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],
        ]];
    }
    return self;
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
    self.title = @"GM Agent";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"新会话"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(newThread)];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"设置"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(openSettings)],
        [[UIBarButtonItem alloc] initWithTitle:@"能力"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(openDev)],
    ];

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
    [self.conversation sendUserText:text];
}

- (void)updateSendButton {
    NSString *sym = self.generating ? @"stop.circle.fill" : @"arrow.up.circle.fill";
    [self.sendButton setImage:[UIImage systemImageNamed:sym] forState:UIControlStateNormal];
    self.sendButton.tintColor = self.generating ? UIColor.systemRedColor : UIColor.labelColor;
}

- (void)newThread {
    [self.conversation newThread];
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
    GMMessage *last = conversation.messages.lastObject;
    self.generating = last.streaming;
    [self updateSendButton];
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
    GMMessage *m = self.conversation.messages[indexPath.row];
    switch (m.role) {
        case GMRoleUser:
            cell.metaLabel.text = @"你";
            cell.bodyLabel.textColor = UIColor.labelColor;
            cell.bodyLabel.text = m.text;
            break;
        case GMRoleTool:
            cell.metaLabel.text = [NSString stringWithFormat:@"工具 · %@", m.toolName ?: @"tool"];
            cell.bodyLabel.textColor = UIColor.tertiaryLabelColor;
            cell.bodyLabel.text = m.toolSummary ?: @"";
            break;
        case GMRoleSystem:
            cell.metaLabel.text = @"系统";
            cell.bodyLabel.textColor = UIColor.secondaryLabelColor;
            cell.bodyLabel.text = m.text;
            break;
        default:
            cell.metaLabel.text = m.streaming ? @"GM Agent · 生成中…" : @"GM Agent";
            cell.bodyLabel.textColor = UIColor.labelColor;
            cell.bodyLabel.text = m.text.length ? m.text : (m.reasoning ?: @"");
            break;
    }
    return cell;
}

@end
