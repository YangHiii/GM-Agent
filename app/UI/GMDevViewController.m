// GM Agent · 开发能力
// - 系统环境自检（越狱 / TrollStore / 沙箱 / 权限）
// - 运行时清单（从 CodexApp-Runtime manifest 拉取，可下载解压）
// - 内置工具探测（git/rg/curl/python/node/clang）
#import "GMDevViewController.h"
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

@interface GMDevViewController ()
@property (nonatomic, strong) UITableView *tableView;
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

    BOOL troll = access("/var/containers/Bundle/trollstore", F_OK) == 0;
    BOOL jb = access("/var/jb", F_OK) == 0;
    BOOL sandbox = NO;
    BOOL noSandbox = access("/usr/bin/ssh", F_OK) == 0 || access("/private/var/mobile", F_OK) == 0;
    sandbox = !noSandbox;

    NSString *ver = [UIDevice currentDevice].systemVersion;
    NSString *model = [UIDevice currentDevice].model;

    [self.envRows addObject:@{@"t": @"系统", @"s": [NSString stringWithFormat:@"%@ · iOS %@", model, ver]}];
    [self.envRows addObject:@{@"t": @"TrollStore", @"s": troll ? @"已安装" : @"未检测到",
                              @"ok": @(troll)}];
    [self.envRows addObject:@{@"t": @"越狱环境", @"s": jb ? @"已检测到 /var/jb" : @"未检测到 /var/jb",
                              @"ok": @(jb)}];
    [self.envRows addObject:@{@"t": @"沙箱", @"s": sandbox ? @"受限（未获得 no-sandbox）" : @"已突破（no-sandbox 生效）",
                              @"ok": @(!sandbox)}];

    // 能否写容器外
    NSString *probe = @"/var/mobile/gm_probe";
    BOOL canWrite = [@"x" writeToFile:probe atomically:YES encoding:NSUTF8StringEncoding error:nil];
    if (canWrite) [[NSFileManager defaultManager] removeItemAtPath:probe error:nil];
    [self.envRows addObject:@{@"t": @"容器外写入", @"s": canWrite ? @"/var/mobile 可写" : @"被拒绝",
                              @"ok": @(canWrite)}];

    // 能否 exec 系统二进制（iOS 禁用 system()，用 popen 探测）
    BOOL canExec = NO;
    FILE *tf = popen("true 2>/dev/null; echo $?", "r");
    if (tf) {
        char tb[8] = {0};
        if (fgets(tb, sizeof(tb), tf) && tb[0] == '0') canExec = YES;
        pclose(tf);
    }
    [self.envRows addObject:@{@"t": @"系统命令执行", @"s": canExec ? @"/usr/bin 可执行" : @"被拒绝或不存在",
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
                        [rows addObject:@{
                            @"t": k,
                            @"s": url.lastPathComponent.length ? url.lastPathComponent : @"(无包名)",
                            @"url": url,
                            @"sha": sha,
                            @"ok": @YES
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

- (void)refreshAll {
    [self buildEnvRows];
    [self probeTools];
    [self loadRuntimes];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return @[@"运行环境", @"内置工具", self.loadingRuntimes ? @"运行时（加载中…）" : @"运行时"][s];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) return @"TrollStore + 越狱环境下，no-sandbox / task_for_pid 等权限才能生效。";
    if (s == 2) return @"运行时来自 CodexApp-Runtime 分发源，包含 Codex、Theos、Python、Node、BuildTools 等。";
    return nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return self.envRows.count;
    if (s == 1) return self.tools.count;
    return MAX(1, self.runtimes.count);
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"dev";
    GMDevCell *c = [tv dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[GMDevCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    c.accessoryType = UITableViewCellAccessoryNone;
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    c.textLabel.textColor = UIColor.labelColor;

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
    if (ip.section != 2 || self.runtimes.count == 0) return;
    NSDictionary *row = self.runtimes[ip.row];
    NSString *url = row[@"url"];
    if (!url.length) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:row[@"t"]
                                                             message:[NSString stringWithFormat:
                                        @"包：%@\n\nSHA256：%@\n\n下载地址已复制到剪贴板。\n（自动安装将在下一版开放）",
                                        row[@"s"], [(row[@"sha"] ?: @"") substringToIndex:MIN(16u, ((NSString *)row[@"sha"]).length)]]
                                                      preferredStyle:UIAlertControllerStyleAlert];
    [UIPasteboard generalPasteboard].string = url;
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
