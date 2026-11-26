// GM Agent · 设置主页面
// 分组：AI 与服务 / 账号与集成 / 聊天与外观 / 能力与工具 / 帮助与诊断
#import "GMSettingsViewController.h"
#import "GMAIAccountViewController.h"
#import "GMDevViewController.h"
#import "GMSessionStore.h"
#import "GMLog.h"
#import "GMSubagentViewController.h"
#import "GMGitHubViewController.h"
#import "GMCompileProtectViewController.h"
#import "GMSkillsViewController.h"
#import "GMDiagnosticsViewController.h"
#import "GMBridge.h"
#import "GMFilesViewController.h"
#import "GMGitHubReposViewController.h"
#import "GMProviderListViewController.h"
#import "GMProviderStore.h"
#import "GMUsageViewController.h"
#import "GMWorkspaceStore.h"

static NSString *const kCell = @"gs";

@interface GMSettingsViewController ()
@property (nonatomic, strong) GMConversation *conversation;
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *groups;
@end

@implementation GMSettingsViewController

- (instancetype)initWithConversation:(GMConversation *)conversation {
    if ((self = [super initWithNibName:nil bundle:nil])) _conversation = conversation;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"设置";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    [self buildGroups];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self buildGroups];
    [self.tableView reloadData];
}

- (void)buildGroups {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    GMProviderRecord *actProv = [GMProviderStore shared].active;
    NSString *provider = actProv
        ? [NSString stringWithFormat:@"%@ · %@", actProv.name ?: actProv.ident, actProv.model ?: @"未选模型"]
        : ([d stringForKey:@"gm.providerName"] ?: @"未配置");
    NSString *agentName = [d stringForKey:@"gm.agentName"] ?: @"GM Agent";
    NSInteger appearance = [d integerForKey:@"gm.appearance"];      // 0 系统 1 浅色 2 深色
    BOOL simple = [d boolForKey:@"gm.simpleDisplay"];

    self.groups = @[
        // AI 与服务
        @[
            @{@"t": @"AI 账号", @"s": provider, @"icon": @"sparkles", @"tint": UIColor.systemBlueColor,
              @"act": @"ai"},
            @{@"t": @"工作区", @"s": [self workspaceSummary], @"icon": @"folder.fill",
              @"tint": UIColor.systemTealColor, @"act": @"workspace"},
            @{@"t": @"对话引擎", @"s": [self engineSummary], @"icon": @"cpu.fill",
              @"tint": UIColor.systemIndigoColor, @"act": @"engine"},
            @{@"t": @"子代理", @"s": [self subagentSummary], @"icon": @"person.2.fill",
              @"tint": UIColor.systemOrangeColor, @"act": @"subagent"},
        ],
        // 账号与集成
        @[
            @{@"t": @"GitHub 账号管理", @"s": [self githubSummary], @"icon": @"chevron.left.forwardslash.chevron.right",
              @"tint": UIColor.systemBlueColor, @"act": @"github"},
        ],
        // 聊天与外观
        @[
            @{@"t": @"外观", @"s": @[@"系统", @"浅色", @"深色"][MIN(appearance, 2)],
              @"icon": @"circle.lefthalf.filled", @"tint": UIColor.systemPurpleColor, @"act": @"appearance"},
            @{@"t": @"对话显示", @"s": simple ? @"简洁" : @"详细",
              @"icon": @"arrow.up.arrow.down.square.fill", @"tint": UIColor.systemIndigoColor, @"act": @"display"},
            @{@"t": @"智能体", @"s": agentName,
              @"icon": @"person.crop.circle.fill", @"tint": UIColor.systemRedColor, @"act": @"agentName"},

        ],
        // 能力与工具
        @[
            @{@"t": @"开发能力", @"s": @"Codex / Theos / 工具链",
              @"icon": @"terminal.fill", @"tint": UIColor.systemTealColor, @"act": @"dev"},
            @{@"t": @"编译保护", @"s": [self protectSummary], @"icon": @"shield.lefthalf.filled",
              @"tint": UIColor.systemPurpleColor, @"act": @"protect"},
            @{@"t": @"Skills 与扩展", @"s": [self skillsSummary], @"icon": @"puzzlepiece.fill",
              @"tint": UIColor.systemBlueColor, @"act": @"skills"},
            @{@"t": @"用量统计", @"s": [self usageSummary], @"icon": @"chart.bar.fill",
              @"tint": UIColor.systemGreenColor, @"act": @"usage"},
            @{@"t": @"文件浏览", @"s": @"浏览设备文件", @"icon": @"folder.fill",
              @"tint": UIColor.systemBlueColor, @"act": @"files"},
            @{@"t": @"存储", @"s": [self storageSummary], @"icon": @"externaldrive.fill",
              @"tint": UIColor.systemGrayColor, @"act": @"storage"},
        ],
        // 帮助与诊断
        @[
            @{@"t": @"运行诊断", @"s": @"逐项检查环境与能力", @"icon": @"waveform.path.ecg",
              @"tint": UIColor.systemRedColor, @"act": @"diag"},
            @{@"t": @"日志", @"s": @"启动与运行日志", @"icon": @"doc.text.fill",
              @"tint": UIColor.systemGrayColor, @"act": @"log"},
            @{@"t": @"关于", @"s": [NSString stringWithFormat:@"v%@",
                                   [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?"],
              @"icon": @"info.circle.fill", @"tint": UIColor.systemBlueColor, @"act": @"about"},
        ],
    ];
}

/// 圆角底色 + 白色 SF Symbol
- (UIImage *)badgeImage:(NSString *)symbol tint:(UIColor *)tint size:(CGFloat)size {
    UIImageSymbolConfiguration *sym = [UIImageSymbolConfiguration configurationWithPointSize:size * 0.58
                                                                                     weight:UIImageSymbolWeightSemibold];
    UIImage *glyph = [[UIImage systemImageNamed:symbol] imageWithConfiguration:sym];
    glyph = [glyph imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.opaque = NO;
    fmt.scale = [UIScreen mainScreen].scale;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size) format:fmt];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size, size)
                                                           cornerRadius:size * 0.25];
        [tint setFill];
        [path fill];
        CGSize gs = glyph.size;
        CGRect gr = CGRectMake((size - gs.width) / 2, (size - gs.height) / 2, gs.width, gs.height);
        [[UIColor whiteColor] setFill];
        [glyph drawInRect:gr blendMode:kCGBlendModeNormal alpha:1.0];
    }];
}

- (NSString *)workspaceSummary {
    GMWorkspace *w = [GMWorkspaceStore shared].active;
    if (!w) return @"未设置";
    return [NSString stringWithFormat:@"%@ · %@", w.name, w.path.lastPathComponent];
}

- (void)manageWorkspace {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"工作区"
                                                            message:@"选择要切换到的项目"
                                                     preferredStyle:UIAlertControllerStyleActionSheet];
    for (GMWorkspace *w in [GMWorkspaceStore shared].workspaces) {
        BOOL cur = [w.ident isEqualToString:[GMWorkspaceStore shared].active.ident ?: @""];
        [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@%@", w.name, cur ? @" ✓" : @""]
                                              style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [[GMWorkspaceStore shared] activateWorkspace:w.ident];
            [self buildGroups];
            [self.tableView reloadData];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    a.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, 200, 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (NSString *)engineSummary {
    NSString *e = [[NSUserDefaults standardUserDefaults] stringForKey:@"gm.engine"] ?: @"auto";
    NSString *model = [[NSUserDefaults standardUserDefaults] stringForKey:@"gm.model"] ?: @"";
    if ([e isEqualToString:@"codex"]) return @"Codex 运行时（手动）";
    if ([e isEqualToString:@"api"]) return @"API 直连（手动）";
    /* auto：猜当前会走哪条 */
    BOOL openai = [model hasPrefix:@"gpt-5"] || [model hasPrefix:@"gpt-6"];
    return openai ? @"自动 · OpenAI 走 Codex" : @"自动 · 第三方走 API";
}

- (void)chooseEngine {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *cur = [d stringForKey:@"gm.engine"] ?: @"auto";

    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"对话引擎"
                                                             message:@"API 直连：直接调模型接口，轻量稳定\nCodex 运行时：使用已安装的 Codex，具备完整工具链与子代理"
                                                      preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"自动（推荐）%@",
                                                 [cur isEqualToString:@"auto"] ? @" ✓" : @""]
                                          style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [d setObject:@"auto" forKey:@"gm.engine"];
        [d synchronize];
        [self buildGroups]; [self.tableView reloadData];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"API 直连%@",
                                                 [cur isEqualToString:@"api"] ? @" ✓" : @""]
                                          style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [d setObject:@"api" forKey:@"gm.engine"];
        [d synchronize];
        [self buildGroups]; [self.tableView reloadData];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Codex 运行时%@",
                                                 [cur isEqualToString:@"codex"] ? @" ✓" : @""]
                                          style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self enableCodex];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    a.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, 200, 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

/// 检查 Codex 是否已安装，然后启用
- (void)enableCodex {
    [[GMBridge shared] call:@"gm/codex/status" params:nil reply:^(id result, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSDictionary *r = [result isKindOfClass:[NSDictionary class]] ? result : @{};
            BOOL available = [r[@"available"] boolValue];
            NSString *bin = r[@"binary"] ?: @"";
            if (!available) {
                [self alert:@"未检测到 Codex 运行时\n\n请先到「能力与工具 → 开发能力」安装 Codex。"];
                return;
            }
            NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
            [d setObject:@"codex" forKey:@"gm.engine"];
            [d synchronize];
            [self buildGroups];
            [self.tableView reloadData];
            [self alert:[NSString stringWithFormat:@"已切换到 Codex 运行时\n\n%@\n\n首次对话会自动启动并握手（约 3-10 秒）。", bin]];
        });
    }];
}

- (NSString *)usageSummary {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    long long in = [[d objectForKey:@"gm.tokens.today.in"] longLongValue];
    long long out = [[d objectForKey:@"gm.tokens.today.out"] longLongValue];
    if (in + out == 0) return @"今日暂无使用";
    return [NSString stringWithFormat:@"今日 ↑%lld ↓%lld", in, out];
}

- (NSString *)subagentSummary {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([[d stringForKey:@"gm.subagent.modelMode"] ?: @"follow" isEqualToString:@"follow"]) return @"跟随主代理";
    return [d stringForKey:@"gm.subagent.model"] ?: @"自定义";
}

- (NSString *)githubSummary {
    NSString *login = [[NSUserDefaults standardUserDefaults] stringForKey:@"gm.github.login"];
    return login.length ? login : @"未连接";
}

- (NSString *)protectSummary {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL strong = [[d stringForKey:@"gm.protect.mode"] ?: @"normal" isEqualToString:@"strong"];
    return strong ? @"强加密" : @"普通";
}

- (NSString *)skillsSummary {
    NSString *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    NSArray *s = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:
                  [lib stringByAppendingPathComponent:@"Skills"] error:nil];
    NSString *g = [[NSUserDefaults standardUserDefaults] stringForKey:@"gm.globalInstruction"];
    BOOL hasG = g.length > 0;
    if (s.count == 0 && !hasG) return @"暂无";
    if (s.count && hasG) return [NSString stringWithFormat:@"%lu 个 Skills · 有全局指令", (unsigned long)s.count];
    if (s.count) return [NSString stringWithFormat:@"%lu 个 Skills", (unsigned long)s.count];
    return @"已配置全局指令";
}

- (NSString *)storageSummary {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    NSString *rt = [lib stringByAppendingPathComponent:@"Runtimes"];
    NSArray *items = [fm contentsOfDirectoryAtPath:rt error:nil];
    if (!items.count) return @"无运行时";
    return [NSString stringWithFormat:@"%lu 个运行时", (unsigned long)items.count];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return self.groups.count; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return @[@"AI 与服务", @"账号与集成", @"聊天与外观", @"能力与工具", @"帮助与诊断"][s];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return self.groups[s].count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:kCell];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCell];
    NSDictionary *row = self.groups[ip.section][ip.row];

    UIListContentConfiguration *cfg = [UIListContentConfiguration subtitleCellConfiguration];
    cfg.text = row[@"t"];
    cfg.secondaryText = row[@"s"];
    cfg.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    cfg.secondaryTextProperties.font = [UIFont systemFontOfSize:12];

    // 生成带圆角底色的图标（contentConfiguration 会覆盖 imageView 背景，必须画进图片里）
    UIImage *icon = [self badgeImage:row[@"icon"] tint:row[@"tint"] size:28];
    cfg.image = icon;
    cfg.imageProperties.reservedLayoutSize = CGSizeMake(28, 28);
    cfg.imageProperties.maximumSize = CGSizeMake(28, 28);
    c.contentConfiguration = cfg;
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *row = self.groups[ip.section][ip.row];
    NSString *act = row[@"act"];

    if ([act isEqualToString:@"ai"]) {
        GMProviderRecord *act0 = [GMProviderStore shared].active;
        if ([[GMProviderStore shared].providers count] <= 1 && act0) {
            /* 只有一个供应商：直接进详情 */
            [self.navigationController pushViewController:
                [[GMAIAccountViewController alloc] initWithConversation:self.conversation
                                                          providerIdent:act0.ident] animated:YES];
        } else {
            [self.navigationController pushViewController:
                [[GMProviderListViewController alloc] initWithConversation:self.conversation] animated:YES];
        }
    } else if ([act isEqualToString:@"dev"]) {
        [self.navigationController pushViewController:[GMDevViewController new] animated:YES];
    } else if ([act isEqualToString:@"diag"]) {
        [self.navigationController pushViewController:[GMDiagnosticsViewController new] animated:YES];
    } else if ([act isEqualToString:@"workspace"]) {
        [self manageWorkspace];
    } else if ([act isEqualToString:@"engine"]) {
        [self chooseEngine];
    } else if ([act isEqualToString:@"subagent"]) {
        [self.navigationController pushViewController:[GMSubagentViewController new] animated:YES];
    } else if ([act isEqualToString:@"github"]) {
        NSString *login = [[NSUserDefaults standardUserDefaults] stringForKey:@"gm.github.login"];
        if (login.length) {
            [self.navigationController pushViewController:[GMGitHubReposViewController new] animated:YES];
        } else {
            [self.navigationController pushViewController:[GMGitHubViewController new] animated:YES];
        }
    } else if ([act isEqualToString:@"protect"]) {
        [self.navigationController pushViewController:[GMCompileProtectViewController new] animated:YES];
    } else if ([act isEqualToString:@"skills"]) {
        [self.navigationController pushViewController:[GMSkillsViewController new] animated:YES];
    } else if ([act isEqualToString:@"log"]) {
        [self showLog];
    } else if ([act isEqualToString:@"appearance"]) {
        [self chooseAppearance];
    } else if ([act isEqualToString:@"display"]) {
        [self chooseDisplay];
    } else if ([act isEqualToString:@"agentName"]) {
        [self editAgentName];
    } else if ([act isEqualToString:@"usage"]) {
        [self.navigationController pushViewController:[GMUsageViewController new] animated:YES];
    } else if ([act isEqualToString:@"files"]) {
        [self.navigationController pushViewController:
            [[GMFilesViewController alloc] initWithPath:@"/var/mobile"] animated:YES];
    } else if ([act isEqualToString:@"storage"]) {
        [self showStorage];
    } else if ([act isEqualToString:@"about"]) {
        [self showAbout];
    } else {
        [self alert:[NSString stringWithFormat:@"%@\n\n该功能正在开发中，后续版本开放。", row[@"t"]]];
    }
}

#pragma mark - 具体动作

- (void)chooseAppearance {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"外观"
                                                             message:nil
                                                      preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *names = @[@"系统", @"浅色", @"深色"];
    for (NSInteger i = 0; i < names.count; i++) {
        [a addAction:[UIAlertAction actionWithTitle:names[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [[NSUserDefaults standardUserDefaults] setInteger:i forKey:@"gm.appearance"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            UIUserInterfaceStyle st = i == 1 ? UIUserInterfaceStyleLight :
                                      (i == 2 ? UIUserInterfaceStyleDark : UIUserInterfaceStyleUnspecified);
            for (UIScene *sc in UIApplication.sharedApplication.connectedScenes)
                if ([sc isKindOfClass:[UIWindowScene class]])
                    for (UIWindow *w in ((UIWindowScene *)sc).windows) w.overrideUserInterfaceStyle = st;
            [self buildGroups];
            [self.tableView reloadData];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    a.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, 200, 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (void)chooseDisplay {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"对话显示"
                                                             message:@"简洁模式会隐藏思考过程与工具详情"
                                                      preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"详细" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"gm.simpleDisplay"];
        [self buildGroups]; [self.tableView reloadData];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"简洁" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"gm.simpleDisplay"];
        [self buildGroups]; [self.tableView reloadData];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    a.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, 200, 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (void)editAgentName {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"智能体名称"
                                                            message:nil
                                                     preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"gm.agentName"] ?: @"GM Agent";
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *n = a.textFields.firstObject.text;
        if (n.length) {
            [[NSUserDefaults standardUserDefaults] setObject:n forKey:@"gm.agentName"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            [self buildGroups]; [self.tableView reloadData];
        }
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)showStorage {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    NSString *rt = [lib stringByAppendingPathComponent:@"Runtimes"];
    NSArray *items = [fm contentsOfDirectoryAtPath:rt error:nil];

    NSMutableString *msg = [NSMutableString string];
    [msg appendFormat:@"运行时目录：\n%@\n\n", rt];
    if (items.count == 0) {
        [msg appendString:@"（空）\n\n到「能力与工具 → 开发能力」安装。"];
    } else {
        for (NSString *it in items) {
            NSString *p = [rt stringByAppendingPathComponent:it];
            unsigned long long size = 0;
            NSDirectoryEnumerator *e = [fm enumeratorAtPath:p];
            for (NSString *sub in e) {
                NSDictionary *attr = [fm attributesOfItemAtPath:[p stringByAppendingPathComponent:sub] error:nil];
                size += [attr fileSize];
            }
            [msg appendFormat:@"• %@  %.1f MB\n", it, size / 1024.0 / 1024.0];
        }
    }

    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"存储"
                                                             message:msg
                                                      preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"清空运行时" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [fm removeItemAtPath:rt error:nil];
        [self buildGroups]; [self.tableView reloadData];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)showAbout {
    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    NSString *msg = [NSString stringWithFormat:
        @"GM Agent\n版本 %@ (%@)\n\n"
        @"自研 iOS Agent：ObjC 界面 + 内置 arm64 引擎。\n"
        @"支持越狱/TrollStore 特权、shell 工具、应用启动、运行时管理。",
        info[@"CFBundleShortVersionString"] ?: @"?", info[@"CFBundleVersion"] ?: @"?"];
    [self alert:msg];
}

- (void)showLog {
    NSString *app = [NSString stringWithContentsOfFile:GMLogPath()
                                              encoding:NSUTF8StringEncoding error:nil] ?: @"(空)";
    NSString *eng = [NSString stringWithContentsOfFile:GMLogEnginePath()
                                              encoding:NSUTF8StringEncoding error:nil] ?: @"(空)";
    NSMutableString *content = [NSMutableString string];
    [content appendString:@"━━━━━ 应用日志 ━━━━━\n"];
    [content appendString:app];
    [content appendString:@"\n\n━━━━━ 引擎日志 ━━━━━\n"];
    [content appendString:eng];
    UIViewController *vc = [UIViewController new];
    vc.title = @"日志";
    vc.view.backgroundColor = UIColor.systemBackgroundColor;
    UITextView *tv = [[UITextView alloc] initWithFrame:vc.view.bounds];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.editable = NO;
    tv.text = content;
    tv.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    [vc.view addSubview:tv];
    vc.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"复制路径"
                                         style:UIBarButtonItemStylePlain
                                        target:self action:@selector(copyLogPath)];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)copyLogPath {
    [UIPasteboard generalPasteboard].string = GMLogPath();
    [self alert:@"路径已复制"];
}

- (void)alert:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"GM Agent"
                                                             message:msg
                                                      preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
