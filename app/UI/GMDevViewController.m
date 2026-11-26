// GM Agent · 开发能力（按 MT Agent 布局）
// 核心能力：Codex / Theos    扩展工具：CoreTools / ReverseTools / BuildTools / Node / Python / OLLVM
#import "GMDevViewController.h"
#import "GMBridge.h"
#import "GMLog.h"

static NSString *const kManifestURL =
    @"https://raw.githubusercontent.com/susu123oss/CodexApp-Runtime/main/Runtime/runtime-manifest.json";

static NSString *RuntimeRoot(void) {
    NSString *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    return [lib stringByAppendingPathComponent:@"Runtimes"];
}

static NSString *FormatSize(long long bytes) {
    if (bytes <= 0) return @"";
    double mb = bytes / (1024.0 * 1024.0);
    if (mb >= 1024) return [NSString stringWithFormat:@"%.1f GB", mb / 1024.0];
    return [NSString stringWithFormat:@"%.1f MB", mb];
}

/// 递归计算目录占用
static long long DirectorySize(NSString *path) {
    NSFileManager *fm = NSFileManager.defaultManager;
    long long total = 0;
    NSDirectoryEnumerator *e = [fm enumeratorAtPath:path];
    for (NSString *sub in e) {
        NSDictionary *attr = [fm attributesOfItemAtPath:[path stringByAppendingPathComponent:sub] error:nil];
        if (attr) total += (long long)[attr fileSize];
    }
    return total;
}

static UIColor *TintColor(NSString *name) {
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"blue": UIColor.systemBlueColor,
            @"cyan": UIColor.systemTealColor,
            @"teal": UIColor.systemTealColor,
            @"green": UIColor.systemGreenColor,
            @"orange": UIColor.systemOrangeColor,
            @"purple": UIColor.systemPurpleColor,
            @"indigo": UIColor.systemIndigoColor,
            @"red": UIColor.systemRedColor,
            @"pink": UIColor.systemPinkColor,
            @"yellow": UIColor.systemYellowColor,
            @"gray": UIColor.systemGrayColor,
            @"mint": UIColor.systemMintColor,
        };
    });
    return map[name.lowercaseString] ?: UIColor.systemBlueColor;
}

#pragma mark - 运行时图标 cell

@interface GMRuntimeCell : UITableViewCell
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UIView *iconBg;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
- (void)configureWithTitle:(NSString *)title
                     state:(NSString *)state
                    symbol:(NSString *)symbol
                     tint:(NSString *)tint
                  loading:(BOOL)loading;
@end

@implementation GMRuntimeCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid])) {
        self.selectionStyle = UITableViewCellSelectionStyleDefault;

        _iconBg = [UIView new];
        _iconBg.translatesAutoresizingMaskIntoConstraints = NO;
        _iconBg.layer.cornerRadius = 9;
        [self.contentView addSubview:_iconBg];

        _iconView = [UIImageView new];
        _iconView.translatesAutoresizingMaskIntoConstraints = NO;
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.tintColor = UIColor.whiteColor;
        [self.contentView addSubview:_iconView];

        _titleLabel = [UILabel new];
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        [self.contentView addSubview:_titleLabel];

        _stateLabel = [UILabel new];
        _stateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _stateLabel.font = [UIFont systemFontOfSize:12];
        _stateLabel.textColor = UIColor.secondaryLabelColor;
        [self.contentView addSubview:_stateLabel];

        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        _spinner.translatesAutoresizingMaskIntoConstraints = NO;
        _spinner.hidesWhenStopped = YES;
        [self.contentView addSubview:_spinner];

        [NSLayoutConstraint activateConstraints:@[
            [_iconBg.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [_iconBg.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_iconBg.widthAnchor constraintEqualToConstant:34],
            [_iconBg.heightAnchor constraintEqualToConstant:34],

            [_iconView.centerXAnchor constraintEqualToAnchor:_iconBg.centerXAnchor],
            [_iconView.centerYAnchor constraintEqualToAnchor:_iconBg.centerYAnchor],
            [_iconView.widthAnchor constraintEqualToConstant:19],
            [_iconView.heightAnchor constraintEqualToConstant:19],

            [_titleLabel.leadingAnchor constraintEqualToAnchor:_iconBg.trailingAnchor constant:12],
            [_titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
            [_titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_spinner.leadingAnchor constant:-8],

            [_stateLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_stateLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
            [_stateLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_spinner.leadingAnchor constant:-8],
            [_stateLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10],

            [_spinner.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [_spinner.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
        ]];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title
                     state:(NSString *)state
                    symbol:(NSString *)symbol
                     tint:(NSString *)tint
                  loading:(BOOL)loading {
    self.titleLabel.text = title;
    self.stateLabel.text = state;
    self.iconBg.backgroundColor = TintColor(tint);
    UIImage *img = [UIImage systemImageNamed:symbol];
    self.iconView.image = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if (loading) [self.spinner startAnimating];
    else [self.spinner stopAnimating];
}

@end

#pragma mark - 控制器

@interface GMDevViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *coreItems;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *toolItems;
@property (nonatomic) BOOL loading;
@property (nonatomic, copy) NSString *installing;
@property (nonatomic, copy) NSString *note;
@end

@implementation GMDevViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"开发能力";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                      target:self action:@selector(loadRuntimes)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 64;
    [self.view addSubview:self.tableView];

    self.coreItems = [NSMutableArray array];
    self.toolItems = [NSMutableArray array];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(runtimeEvent:)
                                                 name:@"gm.runtime"
                                               object:nil];
    [self loadRuntimes];
}

- (void)loadRuntimes {
    self.loading = YES;
    [self.tableView reloadData];

    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:kManifestURL]
                                        cachePolicy:NSURLRequestReloadIgnoringCacheData
                                    timeoutInterval:25];
    __weak typeof(self) wself = self;
    [[[NSURLSession sharedSession] dataTaskWithRequest:req
                                    completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) s = wself;
            if (!s) return;
            s.loading = NO;
            if (err || !data) {
                s.note = [NSString stringWithFormat:@"清单拉取失败：%@", err.localizedDescription ?: @"无数据"];
                [s.tableView reloadData];
                return;
            }
            id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSDictionary *rts = [obj isKindOfClass:[NSDictionary class]] ? obj[@"runtimes"] : nil;
            if (![rts isKindOfClass:[NSDictionary class]]) {
                s.note = @"清单格式异常";
                [s.tableView reloadData];
                return;
            }

            NSMutableArray *core = [NSMutableArray array];
            NSMutableArray *tools = [NSMutableArray array];
            NSArray *keys = [rts allKeys];
            for (NSString *k in keys) {
                NSDictionary *v = rts[k];
                if (![v isKindOfClass:[NSDictionary class]]) continue;

                NSString *group = v[@"group"] ?: @"tools";
                BOOL isCore = [group isEqualToString:@"core"] || [group isEqualToString:@"compiler"];
                NSString *dir = [RuntimeRoot() stringByAppendingPathComponent:k];
                BOOL installed = [[NSFileManager defaultManager] fileExistsAtPath:dir];

                NSString *title = v[@"display_name"] ?: k;
                long long size = [v[@"unpacked_size"] longLongValue];
                if (!size) size = [v[@"download_size"] longLongValue];
                NSString *state;
                if (installed) {
                    state = [NSString stringWithFormat:@"已就绪 · %@", FormatSize(size)];
                } else {
                    state = [NSString stringWithFormat:@"未安装 · %@", FormatSize(size)];
                }
                NSDictionary *ui = [v[@"ui"] isKindOfClass:[NSDictionary class]] ? v[@"ui"] : @{};

                NSMutableDictionary *item = [@{
                    @"id": k,
                    @"title": title,
                    @"state": state,
                    @"symbol": ui[@"symbol"] ?: @"shippingbox.fill",
                    @"tint": ui[@"tint"] ?: @"blue",
                    @"url": v[@"archive_url"] ?: @"",
                    @"sha": v[@"archive_sha256"] ?: @"",
                    @"installed": @(installed),
                    @"order": @([v[@"order"] integerValue]),
                    @"size": @(size),
                    @"summary": v[@"summary"] ?: @"",
                    @"version": v[@"version"] ?: @"",
                } mutableCopy];
                [isCore ? core : tools addObject:item];
            }
            NSSortDescriptor *byOrder = [NSSortDescriptor sortDescriptorWithKey:@"order" ascending:YES];
            s.coreItems = [[core sortedArrayUsingDescriptors:@[byOrder]] mutableCopy];
            s.toolItems = [[tools sortedArrayUsingDescriptors:@[byOrder]] mutableCopy];
            if (s.installing.length) {
                s.note = [NSString stringWithFormat:@"正在安装 %@…", s.installing];
            } else {
                s.note = nil;
            }
            [s.tableView reloadData];
        });
    }] resume];
}

#pragma mark - 安装

- (void)installItem:(NSDictionary *)item {
    if (self.installing.length) {
        [self alert:[NSString stringWithFormat:@"正在安装 %@，请稍候", self.installing]];
        return;
    }
    NSString *name = item[@"title"];
    NSString *url = item[@"url"];
    if (!url.length) { [self alert:@"该运行时没有下载地址"]; return; }

    long long size = [item[@"size"] longLongValue];
    NSString *sizeText = FormatSize(size);

    UIAlertController *a = [UIAlertController alertControllerWithTitle:name
                                                             message:[NSString stringWithFormat:
                                        @"%@\n\n将下载并解压（约 %@），安装到应用数据目录。",
                                        item[@"summary"] ?: @"", sizeText.length ? sizeText : @"未知大小"]
                                                      preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"安装" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self beginInstall:item];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)beginInstall:(NSDictionary *)item {
    self.installing = item[@"title"];
    self.note = [NSString stringWithFormat:@"正在安装 %@…", self.installing];
    [self.tableView reloadData];
    GMLog(@"安装运行时 %@", self.installing);
    [[GMBridge shared] call:@"gm/runtime/install"
                     params:@{@"name": item[@"id"],
                              @"url": item[@"url"],
                              @"sha256": item[@"sha"] ?: @""}
                      reply:^(id r, NSError *e) {
        if (!e) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.installing = nil;
            self.note = [NSString stringWithFormat:@"安装失败：%@", e.localizedDescription];
            [self.tableView reloadData];
        });
    }];
}

- (void)runtimeEvent:(NSNotification *)note {
    NSDictionary *p = note.userInfo;
    if (![p isKindOfClass:[NSDictionary class]]) return;
    NSString *phase = p[@"phase"];
    if ([phase isEqualToString:@"done"]) {
        NSString *name = self.installing;
        self.installing = nil;
        self.note = [NSString stringWithFormat:@"%@ 安装完成", name ?: @""];
        GMLog(@"运行时安装完成: %@", name);
        [self loadRuntimes];
        [self alert:[NSString stringWithFormat:@"%@ 安装完成\n\n%@", name ?: @"", p[@"dest"] ?: @""]];
    } else if ([phase isEqualToString:@"error"]) {
        NSString *name = self.installing;
        self.installing = nil;
        self.note = [NSString stringWithFormat:@"%@ 安装失败", name ?: @""];
        [self.tableView reloadData];
        [self alert:[NSString stringWithFormat:@"%@ 安装失败\n\n%@", name ?: @"", p[@"message"] ?: @"未知错误"]];
    }
}

/// 检查已安装运行时的真实内容，并尝试执行版本命令
- (void)inspectInstalled:(NSDictionary *)it {
    NSString *name = it[@"title"];
    NSString *dir = [RuntimeRoot() stringByAppendingPathComponent:it[@"id"]];
    long long size = DirectorySize(dir);

    NSMutableString *msg = [NSMutableString string];
    [msg appendFormat:@"%@\n\n版本：%@\n磁盘占用：%@\n目录：\n%@\n\n",
                     name, it[@"version"] ?: @"?", FormatSize(size), dir];

    // 列出前 12 个顶层条目
    NSArray *items = [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil];
    [msg appendFormat:@"顶层条目（%lu）：\n", (unsigned long)items.count];
    for (NSUInteger i = 0; i < items.count && i < 12; i++) {
        [msg appendFormat:@"• %@\n", items[i]];
    }
    if (items.count > 12) [msg appendString:@"…\n"];

    // 尝试执行版本命令
    NSDictionary *cmds = @{
        @"codex": @"codex --version 2>&1 || ls bin 2>&1 | head -5",
        @"python": @"python3 --version 2>&1",
        @"node": @"node --version 2>&1",
        @"theos": @"ls $THEOS/bin 2>&1 | head -5",
        @"build_tools": @"cmake --version 2>&1 | head -2",
        @"core_tools": @"git --version 2>&1",
        @"reverse_tools": @"r2 -v 2>&1 | head -2",
        @"ollvm": @"ls bin 2>&1 | head -5",
    };
    NSString *cmd = cmds[it[@"id"]];
    if (cmd.length) {
        NSString *full = [NSString stringWithFormat:@"PATH=%@/bin:$PATH; cd %@ && %@", dir, dir, cmd];
        FILE *f = popen(full.UTF8String, "r");
        if (f) {
            char buf[512] = {0};
            NSMutableString *out = [NSMutableString string];
            while (fgets(buf, sizeof(buf), f)) [out appendString:[NSString stringWithUTF8String:buf] ?: @""];
            pclose(f);
            [msg appendFormat:@"\n执行结果：\n%@", out.length ? out : @"(无输出)"];
        }
    }
    [self alert:msg];
}

- (void)alert:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"GM Agent"
                                                             message:msg
                                                      preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return s == 0 ? @"核心能力" : @"扩展工具";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 1) {
        if (self.note.length) return self.note;
        if (self.loading) return @"正在获取清单…";
        return @"点击任意项可下载安装。运行时来自 CodexApp-Runtime 分发源。";
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    NSArray *items = s == 0 ? self.coreItems : self.toolItems;
    return MAX(items.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSArray *items = ip.section == 0 ? self.coreItems : self.toolItems;
    if (items.count == 0) {
        static NSString *emptyId = @"empty";
        UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:emptyId];
        if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:emptyId];
        c.textLabel.text = self.loading ? @"加载中…" : @"暂无数据";
        c.textLabel.textColor = UIColor.secondaryLabelColor;
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        c.accessoryView = nil;
        return c;
    }

    static NSString *rid = @"rt";
    GMRuntimeCell *c = [tv dequeueReusableCellWithIdentifier:rid];
    if (!c) c = [[GMRuntimeCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:rid];
    NSDictionary *it = items[ip.row];
    BOOL isLoading = [it[@"title"] isEqualToString:self.installing ?: @""];
    [c configureWithTitle:it[@"title"]
                    state:it[@"state"]
                   symbol:it[@"symbol"]
                     tint:it[@"tint"]
                  loading:isLoading];
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSArray *items = ip.section == 0 ? self.coreItems : self.toolItems;
    if (ip.row >= items.count) return;
    NSDictionary *it = items[ip.row];
    if ([it[@"installed"] boolValue]) {
        [self inspectInstalled:it];
        return;
    }
    [self installItem:it];
}

@end
