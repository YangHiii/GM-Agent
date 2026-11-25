// GM Agent · 开发能力
// - 系统环境自检（越狱 / TrollStore / 沙箱 / 权限）
// - 运行时清单（从 CodexApp-Runtime manifest 拉取，可下载解压）
// - 内置工具探测（git/rg/curl/python/node/clang）
#import "GMDevViewController.h"
#import "GMBridge.h"
#import "GMLog.h"
#include <stdio.h>
#include <unistd.h>

static NSString *const kManifestURL =
    @"https://raw.githubusercontent.com/susu123oss/CodexApp-Runtime/main/Runtime/runtime-manifest.json";

@interface GMDevCell : UITableViewCell
@end
@implementation GMDevCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:rid])) {
        self.detailTextLabel.numberOfLines = 2;
        self.detailTextLabel.font = [UIFont systemFontOfSize:11];
        self.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    }
    return self;
}
@end

static NSString *RuntimeRoot(void) {
    NSString *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    return [lib stringByAppendingPathComponent:@"Runtimes"];
}

@interface GMDevViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSString *installing;
@property (nonatomic, copy) NSString *installNote;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *envRows;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *runtimes;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *tools;
@property (nonatomic) BOOL loadingRuntimes;
@end

@implementation GMDevViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"开发能力";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                      target:self action:@selector(refreshAll)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    [self buildEnvRows];
    [self probeTools];
    [self loadRuntimes];
}

#pragma mark - 环境自检

- (void)buildEnvRows {
    self.envRows = [NSMutableArray array];

    // ---- 1. 沙箱是否突破：实测能否读沙箱外 ----
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL canReadOutside = [fm isReadableFileAtPath:@"/var/mobile/Library/Preferences"];
    BOOL canListBundleDir = [fm isReadableFileAtPath:@"/var/containers/Bundle/Application"];
    BOOL canReadJB = [fm isReadableFileAtPath:@"/var/jb"];

    // ---- 2. 越狱探测：roothide 的根是随机化的 .jbroot-XXXX ----
    BOOL jbRoot = canReadJB;
    NSString *jbPath = @"/var/jb";
    if (!jbRoot) {
        NSArray *items = [fm contentsOfDirectoryAtPath:@"/var/containers/Bundle/Application" error:nil];
        for (NSString *it in items) {
            if ([it hasPrefix:@".jbroot"] || [it containsString:@"jbroot"]) {
                jbRoot = YES;
                jbPath = [@"/var/containers/Bundle/Application" stringByAppendingPathComponent:it];
                break;
            }
        }
    }
    if (!jbRoot) {
        // Dopamine / palera1n 常见痕迹
        const char *marks[] = {
            "/usr/lib/libjailbreak.dylib",
            "/var/lib/dpkg/status",
            "/var/mobile/Library/Sileo",
            "/var/mobile/Library/Preferences/com.saurik.Cydia.plist",
            NULL
        };
        for (int i = 0; marks[i]; i++) {
            if (access(marks[i], F_OK) == 0) { jbRoot = YES; jbPath = [NSString stringWithUTF8String:marks[i]]; break; }
        }
    }

    // ---- 3. TrollStore 判定：bundle 位于 /var/containers/Bundle/Application 即侧载 ----
    NSString *bundlePath = [NSBundle mainBundle].bundlePath;
    BOOL troll = [bundlePath containsString:@"/var/containers/Bundle/Application/"];

    NSString *ver = [UIDevice currentDevice].systemVersion;
    NSString *model = [UIDevice currentDevice].model;

    [self.envRows addObject:@{@"t": @"系统", @"s": [NSString stringWithFormat:@"%@ · iOS %@", model, ver]}];
    [self.envRows addObject:@{@"t": @"安装方式", @"s": troll ? @"TrollStore / 侧载（容器外路径）" : bundlePath,
                              @"ok": @(troll)}];
    [self.envRows addObject:@{@"t": @"越狱环境", @"s": jbRoot ? jbPath : @"未检测到越狱根",
                              @"ok": @(jbRoot)}];
    [self.envRows addObject:@{@"t": @"沙箱", @"s": canReadOutside ? @"已突破（可读容器外）" : @"受限（no-sandbox 未生效）",
                              @"ok": @(canReadOutside)}];
    [self.envRows addObject:@{@"t": @"系统目录可读", @"s": canListBundleDir ? @"/var/containers/Bundle/Application ✓" : @"不可读",
                              @"ok": @(canListBundleDir)}];

    // ---- 4. 容器外写入实测 ----
    BOOL canWrite = NO;
    NSString *probe = @"/var/mobile/gm-probe.txt";
    canWrite = [@"x" writeToFile:probe atomically:YES encoding:NSUTF8StringEncoding error:nil];
    if (canWrite) [fm removeItemAtPath:probe error:nil];
    if (!canWrite) {
        probe = [NSTemporaryDirectory() stringByAppendingPathComponent:@"gm-probe.txt"];
        canWrite = [@"x" writeToFile:probe atomically:YES encoding:NSUTF8StringEncoding error:nil];
        if (canWrite) [fm removeItemAtPath:probe error:nil];
    }
    [self.envRows addObject:@{@"t": @"容器外写入", @"s": canWrite ? @"/var/mobile 可写" : @"被拒绝",
                              @"ok": @(canWrite)}];

    // ---- 5. 能否执行系统命令 ----
    BOOL canExec = NO;
    FILE *tf = popen("true 2>/dev/null; echo $?", "r");
    if (tf) {
        char tb[8] = {0};
        if (fgets(tb, sizeof(tb), tf) && tb[0] == '0') canExec = YES;
        pclose(tf);
    }
    [self.envRows addObject:@{@"t": @"系统命令执行", @"s": canExec ? @"可用" : @"被拒绝",
                              @"ok": @(canExec)}];

    [self.tableView reloadData];
}

- (void)probeTools {
    self.tools = [NSMutableArray array];
    NSArray *names = @[@"sh", @"git", @"rg", @"curl", @"python3", @"node", @"clang", @"dpkg", @"ssh"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSMutableArray *found = [NSMutableArray array];
        for (NSString *n in names) {
            NSString *cmd = [NSString stringWithFormat:@"/usr/bin/which %@ 2>/dev/null || /bin/which %@ 2>/dev/null", n, n];
            FILE *f = popen(cmd.UTF8String, "r");
            char buf[512] = {0};
            NSString *path = nil;
            if (f) {
                if (fgets(buf, sizeof(buf), f)) {
                    path = [[NSString stringWithUTF8String:buf]
                            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                }
                pclose(f);
            }
            [found addObject:@{@"t": n, @"s": path.length ? path : @"未安装", @"ok": @(path.length > 0)}];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.tools = found;
            [self.tableView reloadData];
        });
    });
}

#pragma mark - 运行时

- (void)loadRuntimes {
    self.loadingRuntimes = YES;
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
            s.loadingRuntimes = NO;
            NSMutableArray *rows = [NSMutableArray array];
            if (err || !data) {
                [rows addObject:@{@"t": @"清单拉取失败", @"s": err.localizedDescription ?: @"无数据", @"ok": @NO}];
            } else {
                id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                NSDictionary *rts = [obj isKindOfClass:[NSDictionary class]] ? obj[@"runtimes"] : nil;
                if ([rts isKindOfClass:[NSDictionary class]]) {
                    NSArray *keys = [[rts allKeys] sortedArrayUsingSelector:@selector(compare:)];
                    for (NSString *k in keys) {
                        NSDictionary *v = rts[k];
                        NSString *url = v[@"archive_url"] ?: @"";
                        NSString *sha = v[@"archive_sha256"] ?: @"";
                        NSString *dir = [RuntimeRoot() stringByAppendingPathComponent:k];
                        BOOL installed = [[NSFileManager defaultManager] fileExistsAtPath:dir];
                        NSString *sub = installed
                            ? [NSString stringWithFormat:@"已安装 · %@", dir.lastPathComponent]
                            : (url.lastPathComponent.length ? url.lastPathComponent : @"(无包名)");
                        [rows addObject:@{
                            @"t": k,
                            @"s": sub,
                            @"url": url,
                            @"sha": sha,
                            @"ok": @(installed),
                            @"installed": @(installed)
                        }];
                    }
                } else {
                    [rows addObject:@{@"t": @"清单格式异常", @"s": @"缺少 runtimes 字段", @"ok": @NO}];
                }
            }
            s.runtimes = rows;
            [s.tableView reloadData];
        });
    }] resume];
}

- (void)installRuntime:(NSString *)name url:(NSString *)url sha:(NSString *)sha {
    self.installing = name;
    self.installNote = @"准备下载…";
    [self.tableView reloadData];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(runtimeEvent:)
                                                 name:@"gm.runtime"
                                               object:nil];
    GMLog(@"安装运行时 %@ <- %@", name, url);
    [[GMBridge shared] call:@"gm/runtime/install"
                     params:@{@"name": name, @"url": url, @"sha256": sha ?: @""}
                      reply:^(id r, NSError *e) {
        if (e) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.installing = nil;
                self.installNote = e.localizedDescription;
                [self.tableView reloadData];
            });
        }
    }];
}

- (void)runtimeEvent:(NSNotification *)note {
    NSDictionary *p = note.userInfo;
    if (![p isKindOfClass:[NSDictionary class]]) return;
    NSString *name = p[@"name"];
    NSString *phase = p[@"phase"];
    if (![name isEqualToString:self.installing ?: @""]) return;

    if ([phase isEqualToString:@"done"]) {
        self.installing = nil;
        self.installNote = [NSString stringWithFormat:@"%@ 安装完成", name];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:@"gm.runtime" object:nil];
        [self loadRuntimes];
        [self alert:[NSString stringWithFormat:@"%@ 安装完成\n\n%@", name, p[@"dest"] ?: @""]];
    } else if ([phase isEqualToString:@"error"]) {
        self.installing = nil;
        self.installNote = [NSString stringWithFormat:@"%@ 失败：%@", name, p[@"message"] ?: @"未知"];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:@"gm.runtime" object:nil];
        [self.tableView reloadData];
        [self alert:self.installNote];
    } else {
        self.installNote = [NSString stringWithFormat:@"正在安装 %@…", name];
        [self.tableView reloadData];
    }
}

- (void)alert:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"GM Agent"
                                                             message:msg
                                                      preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)refreshAll {
    [self buildEnvRows];
    [self probeTools];
    [self loadRuntimes];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 2) return self.loadingRuntimes ? @"运行时（加载中…）" : @"运行时（点击安装）";
    if (s == 3) return @"诊断";
    return @[@"运行环境", @"内置工具"][s];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 2 && self.installNote.length) return self.installNote;
    if (s == 0) return @"TrollStore + 越狱环境下，no-sandbox / task_for_pid 等权限才能生效。";
    if (s == 2) return @"运行时来自 CodexApp-Runtime 分发源，包含 Codex、Theos、Python、Node、BuildTools 等。";
    return nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return self.envRows.count;
    if (s == 1) return self.tools.count;
    if (s == 3) return 2;
    return MAX(1, self.runtimes.count);
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"dev";
    GMDevCell *c = [tv dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[GMDevCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    c.accessoryType = UITableViewCellAccessoryNone;
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    c.textLabel.textColor = UIColor.labelColor;

    if (ip.section == 3) {
        c.textLabel.text = ip.row == 0 ? @"查看启动日志" : @"复制日志路径";
        c.textLabel.textColor = UIColor.systemBlueColor;
        c.detailTextLabel.text = GMLogPath();
        c.selectionStyle = UITableViewCellSelectionStyleDefault;
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }

    NSDictionary *row = nil;
    if (ip.section == 0 && ip.row < self.envRows.count) row = self.envRows[ip.row];
    else if (ip.section == 1 && ip.row < self.tools.count) row = self.tools[ip.row];
    else if (ip.section == 2) {
        if (self.runtimes.count == 0) {
            c.textLabel.text = self.loadingRuntimes ? @"加载中…" : @"无数据";
            c.detailTextLabel.text = nil;
            return c;
        }
        row = self.runtimes[ip.row];
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        c.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    if (!row) return c;

    c.textLabel.text = row[@"t"];
    c.detailTextLabel.text = row[@"s"];
    if (row[@"ok"]) {
        BOOL ok = [row[@"ok"] boolValue];
        c.textLabel.textColor = ok ? UIColor.labelColor : UIColor.systemOrangeColor;
    }
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 3) {
        if (ip.row == 0) {
            NSString *content = [NSString stringWithContentsOfFile:GMLogPath()
                                                         encoding:NSUTF8StringEncoding error:nil];
            if (!content.length) content = @"(日志为空或文件不存在)";
            UITextView *tv2 = [[UITextView alloc] init];
            tv2.text = content;
            tv2.editable = NO;
            tv2.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
            UIViewController *vc = [UIViewController new];
            vc.title = @"启动日志";
            vc.view.backgroundColor = UIColor.systemBackgroundColor;
            tv2.frame = vc.view.bounds;
            tv2.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [vc.view addSubview:tv2];
            [self.navigationController pushViewController:vc animated:YES];
        } else {
            [UIPasteboard generalPasteboard].string = GMLogPath();
            [self alert:[NSString stringWithFormat:@"路径已复制：\n%@", GMLogPath()]];
        }
        return;
    }
    if (ip.section != 2 || self.runtimes.count == 0) return;
    NSDictionary *row = self.runtimes[ip.row];
    NSString *url = row[@"url"];
    if (!url.length) return;
    NSString *name = row[@"t"];
    NSString *dir = [RuntimeRoot() stringByAppendingPathComponent:name];

    if ([row[@"installed"] boolValue]) {
        [self alert:[NSString stringWithFormat:@"%@ 已安装\n\n%@", name, dir]];
        return;
    }
    if (self.installing.length) {
        [self alert:[NSString stringWithFormat:@"正在安装 %@，请稍候", self.installing]];
        return;
    }

    UIAlertController *a = [UIAlertController alertControllerWithTitle:name
                                                             message:[NSString stringWithFormat:
                                        @"将下载并解压到：\n%@\n\n包：%@\n大小可能较大，请确保网络稳定。",
                                        dir, row[@"s"]]
                                                      preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"安装" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self installRuntime:name url:url sha:row[@"sha"]];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
