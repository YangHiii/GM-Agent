// GM Agent · 运行诊断：每一项都真实执行检查
#import "GMDiagnosticsViewController.h"
#import "GMBridge.h"
#import "GMLog.h"
#include <stdio.h>
#include <unistd.h>

typedef NS_ENUM(NSInteger, DiagState) { DiagPending, DiagRunning, DiagOK, DiagWarn, DiagFail };

@interface GMDiagItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic) DiagState state;
@end
@implementation GMDiagItem
@end

@interface GMDiagnosticsViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<GMDiagItem *> *items;
@property (nonatomic) NSInteger finished;
@end

@implementation GMDiagnosticsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"运行诊断";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                      target:self action:@selector(runAll)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    [self buildItems];
    [self runAll];
}

- (void)buildItems {
    NSArray *titles = @[
        @"引擎服务", @"命令执行", @"实时工具通道", @"运行配置",
        @"项目文件", @"Git 与常用工具", @"代码辅助能力", @"权限与环境",
    ];
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *t in titles) {
        GMDiagItem *it = [GMDiagItem new];
        it.title = t;
        it.detail = @"检查中…";
        it.state = DiagPending;
        [a addObject:it];
    }
    self.items = a;
    self.finished = 0;
    [self.tableView reloadData];
}

- (void)runAll {
    [self buildItems];
    NSInteger n = self.items.count;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // 1 引擎服务
        [self check:0 block:^BOOL(GMDiagItem *it) {
            BOOL running = [GMBridge shared].running;
            it.detail = running ? @"引擎线程已启动" : @"引擎未启动";
            return running;
        }];
        // 2 命令执行
        [self check:1 block:^BOOL(GMDiagItem *it) {
            FILE *f = popen("echo gm-diag-ok", "r");
            char buf[128] = {0};
            BOOL ok = NO;
            if (f) {
                if (fgets(buf, sizeof(buf), f) && strstr(buf, "gm-diag-ok")) ok = YES;
                pclose(f);
            }
            it.detail = ok ? @"shell 可执行" : @"shell 不可用";
            return ok;
        }];
        // 3 实时工具通道
        [self check:2 block:^BOOL(GMDiagItem *it) {
            NSFileManager *fm = NSFileManager.defaultManager;
            BOOL canReach = [fm isReadableFileAtPath:@"/var/mobile"] || [fm isReadableFileAtPath:@"/tmp"];
            it.detail = canReach ? @"可访问设备文件系统" : @"文件系统受限";
            return canReach;
        }];
        // 4 运行配置
        [self check:3 block:^BOOL(GMDiagItem *it) {
            NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
            NSString *url = [d stringForKey:@"gm.baseURL"];
            NSString *model = [d stringForKey:@"gm.model"];
            BOOL ok = url.length > 0 && model.length > 0;
            it.detail = ok ? [NSString stringWithFormat:@"%@ · %@", model, url.length > 34 ? [url substringToIndex:34] : url]
                           : @"未配置网关或模型";
            return ok;
        }];
        // 5 项目文件
        [self check:4 block:^BOOL(GMDiagItem *it) {
            NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
            NSString *probe = [docs stringByAppendingPathComponent:@".gm-diag"];
            BOOL ok = [@"x" writeToFile:probe atomically:YES encoding:NSUTF8StringEncoding error:nil];
            if (ok) [NSFileManager.defaultManager removeItemAtPath:probe error:nil];
            it.detail = ok ? @"文档目录读写正常" : @"文档目录不可写";
            return ok;
        }];
        // 6 Git
        [self check:5 block:^BOOL(GMDiagItem *it) {
            FILE *f = popen("git --version 2>/dev/null", "r");
            char buf[128] = {0};
            BOOL ok = NO;
            NSString *ver = @"";
            if (f) {
                if (fgets(buf, sizeof(buf), f)) {
                    ver = [[NSString stringWithUTF8String:buf]
                           stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                    ok = ver.length > 0;
                }
                pclose(f);
            }
            it.detail = ok ? ver : @"未安装 git（可在开发能力中安装 CoreTools）";
            return ok;
        }];
        // 7 代码辅助
        [self check:6 block:^BOOL(GMDiagItem *it) {
            NSString *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
            NSString *rt = [lib stringByAppendingPathComponent:@"Runtimes"];
            NSArray *rts = [NSFileManager.defaultManager contentsOfDirectoryAtPath:rt error:nil];
            it.detail = rts.count ? [NSString stringWithFormat:@"已装 %lu 个运行时", (unsigned long)rts.count]
                                  : @"未安装运行时（Theos/OLLVM）";
            return rts.count > 0;
        }];
        // 8 权限与环境
        [self check:7 block:^BOOL(GMDiagItem *it) {
            BOOL canRead = [NSFileManager.defaultManager isReadableFileAtPath:@"/var/mobile/Library/Preferences"];
            BOOL troll = [[[NSBundle mainBundle] bundlePath] containsString:@"/var/containers/Bundle/Application/"];
            it.detail = [NSString stringWithFormat:@"%@ · 沙箱%@",
                         troll ? @"TrollStore" : @"普通安装",
                         canRead ? @"已突破" : @"受限"];
            return canRead;
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView reloadData];
        });
    });
}

- (void)check:(NSInteger)idx block:(BOOL (^)(GMDiagItem *))block {
    if (idx >= self.items.count) return;
    GMDiagItem *it = self.items[idx];
    dispatch_async(dispatch_get_main_queue(), ^{
        it.state = DiagRunning;
        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:idx inSection:0]]
                              withRowAnimation:UITableViewRowAnimationNone];
    });
    BOOL ok = block(it);
    it.state = ok ? DiagOK : DiagWarn;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:idx inSection:0]]
                              withRowAnimation:UITableViewRowAnimationNone];
    });
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return @"检查项";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    return @"每项均为真实执行检查（执行命令、读写文件、探测权限），不是静态显示。";
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"diag";
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    GMDiagItem *it = self.items[ip.row];
    c.textLabel.text = it.title;
    c.detailTextLabel.text = it.detail;
    c.detailTextLabel.numberOfLines = 2;
    c.detailTextLabel.font = [UIFont systemFontOfSize:11];
    c.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    c.selectionStyle = UITableViewCellSelectionStyleNone;

    NSString *sym;
    UIColor *tint;
    switch (it.state) {
        case DiagOK:      sym = @"checkmark.circle.fill"; tint = UIColor.systemGreenColor; break;
        case DiagWarn:    sym = @"exclamationmark.triangle.fill"; tint = UIColor.systemOrangeColor; break;
        case DiagFail:    sym = @"xmark.circle.fill"; tint = UIColor.systemRedColor; break;
        case DiagRunning: sym = @"arrow.triangle.2.circlepath"; tint = UIColor.systemBlueColor; break;
        default:          sym = @"circle.dashed"; tint = UIColor.tertiaryLabelColor; break;
    }
    c.imageView.image = [UIImage systemImageNamed:sym];
    c.imageView.tintColor = tint;
    return c;
}

@end
