#import "GMTheosViewController.h"
#import "GMBridge.h"
#import "GMFilesViewController.h"

@interface GMTheosViewController ()
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, copy) NSString *projectPath;
@property (nonatomic, copy) NSString *arch;
@property (nonatomic, copy) NSString *target;
@property (nonatomic, copy) NSString *output;
@property (nonatomic, copy) NSString *status;
@property (nonatomic) BOOL building;
@property (nonatomic, strong) UITextField *pathField;
@end

@implementation GMTheosViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Theos 编译";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.arch = @"arm64";
    self.target = @"package";

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.view addSubview:self.table];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"编译" style:UIBarButtonItemStyleDone
                                        target:self action:@selector(startBuild)];

    [self checkEnv];
}

- (void)checkEnv {
    self.status = @"检测 Theos…";
    __weak typeof(self) w = self;
    [[GMBridge shared] call:@"gm/theos/status" params:nil reply:^(id r, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([r isKindOfClass:[NSDictionary class]] && [r[@"available"] boolValue]) {
                w.status = [NSString stringWithFormat:@"Theos 就绪：%@", r[@"root"]];
            } else {
                w.status = @"Theos 未安装（请先在「开发能力」安装）";
            }
            [w.table reloadData];
        });
    }];
}

- (void)startBuild {
    if (self.building) return;
    if (!self.projectPath.length) {
        [self alert:@"请先选择工程目录"];
        return;
    }
    self.building = YES;
    self.status = @"编译中…";
    [self.table reloadData];

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSMutableArray<NSString *> *fl = [NSMutableArray array];
    if ([d boolForKey:@"gm.protect.str"])   [fl addObject:@"-mllvm -irobf-indbr"];
    if ([d boolForKey:@"gm.protect.int"])   [fl addObject:@"-mllvm -irobf-icall"];
    if ([d boolForKey:@"gm.protect.float"]) [fl addObject:@"-mllvm -irobf-indgv"];
    if ([d boolForKey:@"gm.protect.flatten"]) [fl addObject:@"-mllvm -fla"];
    NSString *flags = [fl componentsJoinedByString:@" "];
    NSDictionary *p = @{@"path": self.projectPath,
                        @"target": self.target ?: @"package",
                        @"arch": self.arch ?: @"arm64",
                        @"flags": flags};
    __weak typeof(self) w = self;
    [[GMBridge shared] call:@"gm/theos/build" params:p reply:^(id r, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{
            w.building = NO;
            if ([r isKindOfClass:[NSDictionary class]]) {
                w.output = r[@"output"] ?: [r description];
                NSInteger code = [r[@"code"] integerValue];
                w.status = code == 0 ? @"✅ 编译成功" : [NSString stringWithFormat:@"❌ 编译失败（code %ld）", (long)code];
            } else {
                w.status = e.localizedDescription ?: @"编译失败";
            }
            [w.table reloadData];
            if ([w.status hasPrefix:@"✅"]) {
                [w alert:[NSString stringWithFormat:@"%@\n\n%@", w.status, w.output ?: @""]];
            }
        });
    }];
}

- (void)alert:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Theos"
                                                            message:msg
                                                     preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return @[@"工程", @"选项", @"输出"][s];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 2;
    if (s == 1) return 2;
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"th";
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cid];
    c.accessoryType = UITableViewCellAccessoryNone;
    c.textLabel.textColor = UIColor.labelColor;

    if (ip.section == 0) {
        if (ip.row == 0) {
            c.textLabel.text = @"工程目录";
            c.detailTextLabel.text = self.projectPath.length ? self.projectPath.lastPathComponent : @"未选择";
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            c.textLabel.text = @"编译方式";
            c.detailTextLabel.text = self.target;
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (ip.section == 1) {
        if (ip.row == 0) {
            c.textLabel.text = @"架构";
            c.detailTextLabel.text = self.arch;
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            c.textLabel.text = @"状态";
            c.detailTextLabel.text = self.status ?: @"-";
            c.detailTextLabel.numberOfLines = 2;
        }
    } else {
        c.textLabel.text = @"查看输出";
        c.detailTextLabel.text = self.output.length ?
            [NSString stringWithFormat:@"%lu 字符", (unsigned long)self.output.length] : @"无";
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0 && ip.row == 0) {
        GMFilesViewController *f = [[GMFilesViewController alloc] initAsPicker:^(NSString *path) {
            self.projectPath = path;
            [self.table reloadData];
        }];
        f.startPath = @"/var/mobile";
        [self.navigationController pushViewController:f animated:YES];
    } else if (ip.section == 0 && ip.row == 1) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"编译方式"
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSString *t in @[@"package", @"clean", @"all"]) {
            [a addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
                self.target = t; [self.table reloadData];
            }]];
        }
        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        a.popoverPresentationController.sourceView = tv;
        a.popoverPresentationController.sourceRect = [tv rectForRowAtIndexPath:ip];
        [self presentViewController:a animated:YES completion:nil];
    } else if (ip.section == 1 && ip.row == 0) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"架构"
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSString *t in @[@"arm64", @"arm64e", @"arm64 arm64e"]) {
            [a addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
                self.arch = t; [self.table reloadData];
            }]];
        }
        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        a.popoverPresentationController.sourceView = tv;
        a.popoverPresentationController.sourceRect = [tv rectForRowAtIndexPath:ip];
        [self presentViewController:a animated:YES completion:nil];
    } else if (ip.section == 2) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"编译输出"
                                                                message:self.output ?: @"(无)"
                                                         preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [UIPasteboard generalPasteboard].string = self.output ?: @"";
        }]];
        [a addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    }
}

@end
