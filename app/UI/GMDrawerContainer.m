// GM Agent · 侧边栏 + 抽屉容器（对齐 MT 图 1 布局）
#import "GMDrawerContainer.h"
#import "GMConversation.h"
#import "GMSessionStore.h"
#import "GMLog.h"
#import "GMUsageViewController.h"

static const CGFloat kSidebarRatio = 0.78;   // 侧边栏占屏宽比例
static const CGFloat kCorner = 24.0;

#pragma mark - 会话行

@interface GMSidebarSessionCell : UITableViewCell
@property (nonatomic, strong) UIView *dot;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UIButton *moreButton;
@end

@implementation GMSidebarSessionCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid])) {
        self.backgroundColor = UIColor.clearColor;
        self.selectionStyle = UITableViewCellSelectionStyleDefault;

        _dot = [UIView new];
        _dot.translatesAutoresizingMaskIntoConstraints = NO;
        _dot.layer.cornerRadius = 7;
        [self.contentView addSubview:_dot];

        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        _titleLabel.textColor = UIColor.labelColor;
        [self.contentView addSubview:_titleLabel];

        _timeLabel = [UILabel new];
        _timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _timeLabel.font = [UIFont systemFontOfSize:12];
        _timeLabel.textColor = UIColor.tertiaryLabelColor;
        _timeLabel.hidden = YES;
        [self.contentView addSubview:_timeLabel];

        _moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _moreButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_moreButton setImage:[UIImage systemImageNamed:@"ellipsis"] forState:UIControlStateNormal];
        _moreButton.tintColor = UIColor.tertiaryLabelColor;
        [self.contentView addSubview:_moreButton];

        [NSLayoutConstraint activateConstraints:@[
            [_dot.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:18],
            [_dot.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_dot.widthAnchor constraintEqualToConstant:14],
            [_dot.heightAnchor constraintEqualToConstant:14],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_dot.trailingAnchor constant:12],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_moreButton.leadingAnchor constant:-8],

            [_moreButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-10],
            [_moreButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_moreButton.widthAnchor constraintEqualToConstant:24],
            [_moreButton.heightAnchor constraintEqualToConstant:24],
        ]];
    }
    return self;
}
@end

#pragma mark - 侧边栏

@interface GMSidebarViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *folderButton;
@property (nonatomic, strong) UIButton *composeButton;
@property (nonatomic, strong) UILabel *sectionLabel;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<GMSessionMeta *> *sessions;
@property (nonatomic, strong) UIView *usageCard;
@property (nonatomic, strong) UILabel *usageTitle;
@property (nonatomic, strong) UILabel *usageSub;
@property (nonatomic, strong) UIView *providerRow;
@property (nonatomic, strong) UILabel *providerTitle;
@property (nonatomic, strong) UILabel *providerSub;
@property (nonatomic, strong) UILabel *versionLabel;
@end

@implementation GMSidebarViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    [self buildUI];
    [self reload];
}

- (void)buildUI {
    UIView *v = self.view;

    /* 标题 */
    _titleLabel = [UILabel new];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.text = @"GM Agent";
    _titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    [v addSubview:_titleLabel];

    /* 右上"更多" */
    UIButton *more = [UIButton buttonWithType:UIButtonTypeSystem];
    more.translatesAutoresizingMaskIntoConstraints = NO;
    [more setImage:[UIImage systemImageNamed:@"ellipsis.circle"] forState:UIControlStateNormal];
    more.tintColor = UIColor.labelColor;
    [more addTarget:self action:@selector(showMore) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:more];

    /* 顶部：文件夹 + 新对话 */
    _folderButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _folderButton.translatesAutoresizingMaskIntoConstraints = NO;
    _folderButton.backgroundColor = UIColor.secondarySystemBackgroundColor;
    _folderButton.layer.cornerRadius = 12;
    [_folderButton setImage:[UIImage systemImageNamed:@"folder.badge.plus"] forState:UIControlStateNormal];
    _folderButton.tintColor = UIColor.labelColor;
    [_folderButton addTarget:self action:@selector(newWorkspace) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:_folderButton];

    _composeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _composeButton.translatesAutoresizingMaskIntoConstraints = NO;
    _composeButton.backgroundColor = [UIColor colorWithRed:0.16 green:0.45 blue:0.98 alpha:1.0];
    _composeButton.layer.cornerRadius = 12;
    [_composeButton setTitle:@"+  新对话" forState:UIControlStateNormal];
    [_composeButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _composeButton.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [_composeButton addTarget:self action:@selector(newChat) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:_composeButton];

    /* 分组标题 */
    _sectionLabel = [UILabel new];
    _sectionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _sectionLabel.text = @"项目";
    _sectionLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _sectionLabel.textColor = UIColor.secondaryLabelColor;
    [v addSubview:_sectionLabel];

    /* 会话列表 */
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _table.translatesAutoresizingMaskIntoConstraints = NO;
    _table.backgroundColor = UIColor.clearColor;
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.dataSource = self;
    _table.delegate = self;
    _table.rowHeight = 44;
    _table.contentInset = UIEdgeInsetsMake(0, 0, 8, 0);
    [v addSubview:_table];

    /* 底部用量卡 */
    _usageCard = [UIView new];
    _usageCard.translatesAutoresizingMaskIntoConstraints = NO;
    _usageCard.backgroundColor = UIColor.secondarySystemBackgroundColor;
    _usageCard.layer.cornerRadius = 12;
    [v addSubview:_usageCard];

    UIImageView *chart = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chart.bar.fill"]];
    chart.translatesAutoresizingMaskIntoConstraints = NO;
    chart.tintColor = UIColor.systemGreenColor;
    [_usageCard addSubview:chart];

    _usageTitle = [UILabel new];
    _usageTitle.translatesAutoresizingMaskIntoConstraints = NO;
    _usageTitle.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _usageTitle.text = @"今日 ¥0.00 · 累计 ¥0.00";
    [_usageCard addSubview:_usageTitle];

    _usageSub = [UILabel new];
    _usageSub.translatesAutoresizingMaskIntoConstraints = NO;
    _usageSub.font = [UIFont systemFontOfSize:11];
    _usageSub.textColor = UIColor.secondaryLabelColor;
    _usageSub.text = @"第三方 API 用量";
    [_usageCard addSubview:_usageSub];

    UIImageView *chev = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    chev.translatesAutoresizingMaskIntoConstraints = NO;
    chev.tintColor = UIColor.tertiaryLabelColor;
    [_usageCard addSubview:chev];

    UITapGestureRecognizer *tapUsage = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openUsage)];
    [_usageCard addGestureRecognizer:tapUsage];

    /* 供应商行 */
    _providerRow = [UIView new];
    _providerRow.translatesAutoresizingMaskIntoConstraints = NO;
    [v addSubview:_providerRow];

    UIImageView *globe = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"globe"]];
    globe.translatesAutoresizingMaskIntoConstraints = NO;
    globe.tintColor = UIColor.labelColor;
    [_providerRow addSubview:globe];

    _providerTitle = [UILabel new];
    _providerTitle.translatesAutoresizingMaskIntoConstraints = NO;
    _providerTitle.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    _providerTitle.text = @"新建供应商";
    [_providerRow addSubview:_providerTitle];

    _providerSub = [UILabel new];
    _providerSub.translatesAutoresizingMaskIntoConstraints = NO;
    _providerSub.font = [UIFont systemFontOfSize:13];
    _providerSub.textColor = UIColor.secondaryLabelColor;
    _providerSub.text = @"未配置";
    [_providerRow addSubview:_providerSub];

    UIButton *gear = [UIButton buttonWithType:UIButtonTypeSystem];
    gear.translatesAutoresizingMaskIntoConstraints = NO;
    [gear setImage:[UIImage systemImageNamed:@"gearshape"] forState:UIControlStateNormal];
    gear.tintColor = UIColor.tertiaryLabelColor;
    [gear addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [_providerRow addSubview:gear];

    UITapGestureRecognizer *tapProv = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openSettings)];
    [_providerRow addGestureRecognizer:tapProv];

    _versionLabel = [UILabel new];
    _versionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _versionLabel.font = [UIFont systemFontOfSize:11];
    _versionLabel.textColor = UIColor.tertiaryLabelColor;
    _versionLabel.textAlignment = NSTextAlignmentCenter;
    NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    _versionLabel.text = [NSString stringWithFormat:@"🚀  GM Agent  v%@", ver];
    [v addSubview:_versionLabel];

    UILayoutGuide *safe = v.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_titleLabel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10],
        [_titleLabel.centerXAnchor constraintEqualToAnchor:v.centerXAnchor],

        [more.centerYAnchor constraintEqualToAnchor:_titleLabel.centerYAnchor],
        [more.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-16],
        [more.widthAnchor constraintEqualToConstant:28],
        [more.heightAnchor constraintEqualToConstant:28],

        [_folderButton.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:16],
        [_folderButton.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:14],
        [_folderButton.widthAnchor constraintEqualToConstant:56],
        [_folderButton.heightAnchor constraintEqualToConstant:56],

        [_composeButton.leadingAnchor constraintEqualToAnchor:_folderButton.trailingAnchor constant:8],
        [_composeButton.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-16],
        [_composeButton.centerYAnchor constraintEqualToAnchor:_folderButton.centerYAnchor],
        [_composeButton.heightAnchor constraintEqualToConstant:56],

        [_sectionLabel.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:20],
        [_sectionLabel.topAnchor constraintEqualToAnchor:_folderButton.bottomAnchor constant:16],

        [_table.leadingAnchor constraintEqualToAnchor:v.leadingAnchor],
        [_table.trailingAnchor constraintEqualToAnchor:v.trailingAnchor],
        [_table.topAnchor constraintEqualToAnchor:_sectionLabel.bottomAnchor constant:6],
        [_table.bottomAnchor constraintEqualToAnchor:_usageCard.topAnchor constant:-8],

        [_usageCard.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:16],
        [_usageCard.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-16],
        [_usageCard.heightAnchor constraintEqualToConstant:56],

        [chart.leadingAnchor constraintEqualToAnchor:_usageCard.leadingAnchor constant:12],
        [chart.centerYAnchor constraintEqualToAnchor:_usageCard.centerYAnchor],
        [chart.widthAnchor constraintEqualToConstant:22],
        [chart.heightAnchor constraintEqualToConstant:22],

        [_usageTitle.leadingAnchor constraintEqualToAnchor:chart.trailingAnchor constant:10],
        [_usageTitle.topAnchor constraintEqualToAnchor:_usageCard.topAnchor constant:10],
        [_usageTitle.trailingAnchor constraintLessThanOrEqualToAnchor:chev.leadingAnchor constant:-8],

        [_usageSub.leadingAnchor constraintEqualToAnchor:_usageTitle.leadingAnchor],
        [_usageSub.topAnchor constraintEqualToAnchor:_usageTitle.bottomAnchor constant:2],

        [chev.trailingAnchor constraintEqualToAnchor:_usageCard.trailingAnchor constant:-12],
        [chev.centerYAnchor constraintEqualToAnchor:_usageCard.centerYAnchor],
        [chev.widthAnchor constraintEqualToConstant:12],
        [chev.heightAnchor constraintEqualToConstant:16],

        [_providerRow.leadingAnchor constraintEqualToAnchor:_usageCard.leadingAnchor],
        [_providerRow.trailingAnchor constraintEqualToAnchor:_usageCard.trailingAnchor],
        [_providerRow.topAnchor constraintEqualToAnchor:_usageCard.bottomAnchor constant:14],
        [_providerRow.heightAnchor constraintEqualToConstant:44],

        [globe.leadingAnchor constraintEqualToAnchor:_providerRow.leadingAnchor constant:4],
        [globe.centerYAnchor constraintEqualToAnchor:_providerRow.centerYAnchor],
        [globe.widthAnchor constraintEqualToConstant:24],
        [globe.heightAnchor constraintEqualToConstant:24],

        [_providerTitle.leadingAnchor constraintEqualToAnchor:globe.trailingAnchor constant:10],
        [_providerTitle.topAnchor constraintEqualToAnchor:_providerRow.topAnchor constant:3],

        [_providerSub.leadingAnchor constraintEqualToAnchor:_providerTitle.leadingAnchor],
        [_providerSub.topAnchor constraintEqualToAnchor:_providerTitle.bottomAnchor constant:1],

        [gear.trailingAnchor constraintEqualToAnchor:_providerRow.trailingAnchor constant:-4],
        [gear.centerYAnchor constraintEqualToAnchor:_providerRow.centerYAnchor],
        [gear.widthAnchor constraintEqualToConstant:26],
        [gear.heightAnchor constraintEqualToConstant:26],

        [_versionLabel.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:16],
        [_versionLabel.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-16],
        [_versionLabel.topAnchor constraintEqualToAnchor:_providerRow.bottomAnchor constant:8],
        [_versionLabel.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],
    ]];
}

- (void)reload {
    self.sessions = [GMSessionStore shared].sessions;
    [self.table reloadData];

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *host = [d stringForKey:@"gm.providerName"];
    NSString *model = [d stringForKey:@"gm.model"] ?: @"未配置";
    self.providerTitle.text = host.length ? @"当前供应商" : @"新建供应商";
    self.providerSub.text = host.length ? [NSString stringWithFormat:@"%@ · %@", host, model] : @"未配置";

    long long in = [[d objectForKey:@"gm.tokens.in"] longLongValue];
    long long out = [[d objectForKey:@"gm.tokens.out"] longLongValue];
    if (in + out > 0) {
        self.usageTitle.text = [NSString stringWithFormat:@"↑%lld ↓%lld tokens", in, out];
    } else {
        self.usageTitle.text = @"今日 ¥0.00 · 累计 ¥0.00";
    }
    self.usageSub.text = @"第三方 API 用量";
}

#pragma mark - 动作

- (void)newChat {
    if (self.onNewSession) self.onNewSession();
    [self reload];
}

- (void)newWorkspace {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"新建项目"
                                                            message:@"项目分组将在下一阶段开放，当前所有会话归入默认分组。"
                                                     preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)showMore {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:nil
                                                      preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"设置" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        if (self.onOpenSettings) self.onOpenSettings();
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    a.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width - 40, 40, 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (void)openUsage {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"gm.openUsage" object:nil];
}

- (void)openSettings {
    if (self.onOpenSettings) self.onOpenSettings();
}

- (void)alert:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"GM Agent" message:msg
                                                     preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return self.sessions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"s";
    GMSidebarSessionCell *c = [tv dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[GMSidebarSessionCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
    GMSessionMeta *m = self.sessions[ip.row];
    c.titleLabel.text = m.title;
    BOOL cur = [m.threadID isEqualToString:[[GMSessionStore shared] currentThreadID] ?: @""];
    c.dot.backgroundColor = cur ? UIColor.systemBlueColor : UIColor.tertiaryLabelColor;
    c.dot.hidden = !cur;
    c.titleLabel.textColor = cur ? UIColor.labelColor : UIColor.secondaryLabelColor;
    c.moreButton.tag = ip.row;
    [c.moreButton removeTarget:nil action:nil forControlEvents:UIControlEventAllEvents];
    [c.moreButton addTarget:self action:@selector(sessionMore:) forControlEvents:UIControlEventTouchUpInside];
    return c;
}

- (void)sessionMore:(UIButton *)b {
    NSInteger idx = b.tag;
    if (idx < 0 || idx >= self.sessions.count) return;
    GMSessionMeta *m = self.sessions[idx];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:m.title message:nil
                                                      preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"删除会话" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [[GMSessionStore shared] removeSession:m.threadID];
        [self reload];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = b;
    a.popoverPresentationController.sourceRect = b.bounds;
    [self presentViewController:a animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    GMSessionMeta *m = self.sessions[ip.row];
    if (self.onSelectSession) self.onSelectSession(m.threadID);
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    GMSessionMeta *m = self.sessions[ip.row];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                      title:@"删除"
                                                                    handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [[GMSessionStore shared] removeSession:m.threadID];
        [self reload];
        done(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

@end

#pragma mark - 抽屉容器

@interface GMDrawerContainer () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIViewController *content;
@property (nonatomic, strong) GMSidebarViewController *sidebar;
@property (nonatomic, strong) UIView *overlay;
@property (nonatomic, strong) UIView *sidebarHost;
@property (nonatomic) CGFloat sidebarWidth;
@property (nonatomic) BOOL open;
@end

@implementation GMDrawerContainer

- (instancetype)initWithContent:(UIViewController *)content sidebar:(GMSidebarViewController *)sidebar {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _content = content;
        _sidebar = sidebar;
    }
    return self;
}

- (BOOL)isDrawerOpen { return self.open; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.sidebarWidth = self.view.bounds.size.width * kSidebarRatio;

    /* 内容层 */
    [self addChildViewController:self.content];
    self.content.view.frame = self.view.bounds;
    self.content.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.content.view];
    [self.content didMoveToParentViewController:self];

    /* 遮罩 */
    self.overlay = [[UIView alloc] initWithFrame:self.view.bounds];
    self.overlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    self.overlay.alpha = 0;
    self.overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissTap)];
    [self.overlay addGestureRecognizer:tap];
    [self.view addSubview:self.overlay];

    /* 侧边栏宿主 */
    self.sidebarHost = [[UIView alloc] initWithFrame:CGRectMake(-self.sidebarWidth, 0,
                                                                self.sidebarWidth, self.view.bounds.size.height)];
    self.sidebarHost.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    self.sidebarHost.layer.cornerRadius = kCorner;
    self.sidebarHost.layer.maskedCorners = kCALayerMaxXMinYCorner | kCALayerMaxXMaxYCorner;
    self.sidebarHost.layer.masksToBounds = YES;
    [self.view addSubview:self.sidebarHost];

    [self addChildViewController:self.sidebar];
    self.sidebar.view.frame = self.sidebarHost.bounds;
    self.sidebar.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.sidebarHost addSubview:self.sidebar.view];
    [self.sidebar didMoveToParentViewController:self];

    /* 手势 */
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    pan.delegate = self;
    [self.view addGestureRecognizer:pan];

    UIScreenEdgePanGestureRecognizer *edge =
        [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(handleEdgePan:)];
    edge.edges = UIRectEdgeLeft;
    edge.delegate = self;
    [self.view addGestureRecognizer:edge];

    __weak typeof(self) wself = self;
    self.sidebar.onSelectSession = ^(NSString *tid) {
        __strong typeof(wself) s = wself;
        [s.sidebar.conversation loadThread:tid];
        [s closeDrawerAnimated:YES];
    };
    self.sidebar.onNewSession = ^{
        __strong typeof(wself) s = wself;
        GMSessionMeta *m = [[GMSessionStore shared] createSessionWithTitle:@"新对话"];
        [[GMSessionStore shared] setCurrentThreadID:m.threadID];
        [s.sidebar.conversation newThread];
        [s.sidebar reload];
        [s closeDrawerAnimated:YES];
    };
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(toggleDrawer)
                                               name:@"gm.toggleDrawer" object:nil];

    self.sidebar.onOpenSettings = ^{
        __strong typeof(wself) s = wself;
        [s closeDrawerAnimated:YES];
        if ([s.content isKindOfClass:[UINavigationController class]]) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"gm.openSettings"
                                                                object:nil];
        }
    };
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.sidebarWidth = self.view.bounds.size.width * kSidebarRatio;
    CGRect f = self.sidebarHost.frame;
    f.size.width = self.sidebarWidth;
    f.size.height = self.view.bounds.size.height;
    f.origin.x = self.open ? 0 : -self.sidebarWidth;
    self.sidebarHost.frame = f;
}

- (void)toggleDrawer {
    if (self.open) [self closeDrawerAnimated:YES];
    else [self openDrawerAnimated:YES];
}

- (void)dismissTap { [self closeDrawerAnimated:YES]; }

- (void)openDrawerAnimated:(BOOL)animated {
    self.open = YES;
    [self.sidebar reload];
    void (^apply)(void) = ^{
        CGRect f = self.sidebarHost.frame;
        f.origin.x = 0;
        self.sidebarHost.frame = f;
        self.overlay.alpha = 1;
    };
    if (animated) {
        [UIView animateWithDuration:0.26 delay:0
             usingSpringWithDamping:0.9 initialSpringVelocity:0.4
                            options:UIViewAnimationOptionCurveEaseOut animations:apply completion:nil];
    } else {
        apply();
    }
}

- (void)closeDrawerAnimated:(BOOL)animated {
    self.open = NO;
    void (^apply)(void) = ^{
        CGRect f = self.sidebarHost.frame;
        f.origin.x = -self.sidebarWidth;
        self.sidebarHost.frame = f;
        self.overlay.alpha = 0;
    };
    if (animated) {
        [UIView animateWithDuration:0.24 animations:apply];
    } else {
        apply();
    }
}

- (void)handleEdgePan:(UIScreenEdgePanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.view];
    switch (g.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged: {
            CGFloat x = MAX(-self.sidebarWidth, MIN(0, -self.sidebarWidth + t.x));
            CGRect f = self.sidebarHost.frame;
            f.origin.x = x;
            self.sidebarHost.frame = f;
            self.overlay.alpha = 1.0 - (x / -self.sidebarWidth);
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            CGPoint v = [g velocityInView:self.view];
            if (v.x > 300 || self.sidebarHost.frame.origin.x > -self.sidebarWidth * 0.5)
                [self openDrawerAnimated:YES];
            else
                [self closeDrawerAnimated:YES];
            break;
        }
        default: break;
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)g {
    if (!self.open) return;
    CGPoint t = [g translationInView:self.view];
    switch (g.state) {
        case UIGestureRecognizerStateChanged: {
            CGFloat x = MAX(-self.sidebarWidth, MIN(0, t.x));
            CGRect f = self.sidebarHost.frame;
            f.origin.x = x;
            self.sidebarHost.frame = f;
            self.overlay.alpha = 1.0 + (x / self.sidebarWidth);
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            if (self.sidebarHost.frame.origin.x < -self.sidebarWidth * 0.3)
                [self closeDrawerAnimated:YES];
            else
                [self openDrawerAnimated:YES];
            break;
        }
        default: break;
    }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if ([g isKindOfClass:[UIScreenEdgePanGestureRecognizer class]]) return !self.open;
    if ([g isKindOfClass:[UIPanGestureRecognizer class]]) return self.open;
    return YES;
}

@end
