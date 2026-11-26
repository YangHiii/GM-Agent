// GM Agent · 编译保护：模式 + 四项保护开关，生成真实 OLLVM 编译参数
#import "GMCompileProtectViewController.h"
#import "GMLog.h"

@interface GMCompileProtectViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSString *mode;        // normal | strong
@property (nonatomic, copy) NSString *style;       // single | combo
@property (nonatomic) BOOL strEnc;
@property (nonatomic) BOOL intEnc;
@property (nonatomic) BOOL floatEnc;
@property (nonatomic) BOOL flatten;
@end

@implementation GMCompileProtectViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"编译保护";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    self.mode = [d stringForKey:@"gm.protect.mode"] ?: @"normal";
    self.style = [d stringForKey:@"gm.protect.style"] ?: @"combo";
    self.strEnc = [d objectForKey:@"gm.protect.str"] ? [d boolForKey:@"gm.protect.str"] : YES;
    self.intEnc = [d objectForKey:@"gm.protect.int"] ? [d boolForKey:@"gm.protect.int"] : YES;
    self.floatEnc = [d objectForKey:@"gm.protect.float"] ? [d boolForKey:@"gm.protect.float"] : YES;
    self.flatten = [d objectForKey:@"gm.protect.flatten"] ? [d boolForKey:@"gm.protect.flatten"] : YES;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
}

- (void)persist {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:self.mode forKey:@"gm.protect.mode"];
    [d setObject:self.style forKey:@"gm.protect.style"];
    [d setBool:self.strEnc forKey:@"gm.protect.str"];
    [d setBool:self.intEnc forKey:@"gm.protect.int"];
    [d setBool:self.floatEnc forKey:@"gm.protect.float"];
    [d setBool:self.flatten forKey:@"gm.protect.flatten"];
    [d synchronize];
    GMLog(@"编译保护: mode=%@ style=%@ str=%d int=%d float=%d flat=%d",
          self.mode, self.style, self.strEnc, self.intEnc, self.floatEnc, self.flatten);
}

/// 生成真实的 OLLVM 编译参数（供终端/theos 使用）
- (NSString *)flagsString {
    NSMutableArray *f = [NSMutableArray array];
    BOOL strong = [self.mode isEqualToString:@"strong"];
    if (self.strEnc) [f addObject:@"-mllvm -irobf-indbr"];
    if (self.strEnc) [f addObject:@"-mllvm -irobf-istr"];
    if (self.intEnc) [f addObject:@"-mllvm -irobf-indgv"];
    if (self.floatEnc) [f addObject:@"-mllvm -irobf-icall"];
    if (self.flatten) [f addObject:@"-mllvm -fla"];
    if (strong) {
        [f addObject:@"-mllvm -split"];
        [f addObject:@"-mllvm -split_num=3"];
        [f addObject:@"-mllvm -bcf"];
        [f addObject:@"-mllvm -bcf_loop=3"];
    }
    if (f.count == 0) return @"（未启用任何保护）";
    return [f componentsJoinedByString:@" "];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return @[@"编译方式", @"保护方式", @"保护能力", @"操作"][s];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) return self.modeIsStrong
        ? @"开启后使用保护编译前端；最终链接仍沿用稳定的 Theos 工具链。编译时间和成品体积可能略有增加。"
        : @"普通编译速度更快、兼容性最好，适合日常开发和调试。";
    if (s == 2) return @"保护参数会在调用 clang 时自动注入；需要先安装「开发能力 → OLLVM」运行时。";
    if (s == 3) return [NSString stringWithFormat:@"当前参数：\n%@", [self flagsString]];
    return nil;
}

- (BOOL)modeIsStrong { return [self.mode isEqualToString:@"strong"]; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 1;
    if (s == 1) return 1;
    if (s == 2) return 4;
    return 2;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"c";
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    c.accessoryView = nil;
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    c.textLabel.textColor = UIColor.labelColor;
    c.detailTextLabel.text = nil;
    c.imageView.image = nil;
    c.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;

    if (ip.section == 0) {
        c.textLabel.text = @"编译模式";
        UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"普通", @"强加密"]];
        seg.selectedSegmentIndex = self.modeIsStrong ? 1 : 0;
        [seg addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = seg;
    } else if (ip.section == 1) {
        c.textLabel.text = @"保护方式";
        UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"单项", @"组合"]];
        seg.selectedSegmentIndex = [self.style isEqualToString:@"combo"] ? 1 : 0;
        [seg addTarget:self action:@selector(styleChanged:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = seg;
    } else if (ip.section == 2) {
        NSArray *titles = @[@"字符串加密", @"整数常量加密", @"浮点常量加密", @"控制流扁平化"];
        NSArray *subs = @[@"加密程序中的字符串内容",
                          @"混淆整数常量，增加静态分析难度",
                          @"混淆浮点常量，增加静态分析难度",
                          @"将控制流转换为更难分析的分发结构"];
        BOOL on = @[ @(self.strEnc), @(self.intEnc), @(self.floatEnc), @(self.flatten) ][ip.row];
        c.textLabel.text = titles[ip.row];
        c.detailTextLabel.text = subs[ip.row];
        c.detailTextLabel.font = [UIFont systemFontOfSize:11];
        c.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        UISwitch *sw = [UISwitch new];
        sw.on = on;
        sw.tag = 100 + ip.row;
        [sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = sw;
    } else {
        if (ip.row == 0) {
            c.textLabel.text = @"复制编译参数";
            c.textLabel.textColor = UIColor.systemBlueColor;
            c.accessoryType = UITableViewCellAccessoryNone;
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else {
            c.textLabel.text = @"恢复默认（全部开启）";
            c.textLabel.textColor = UIColor.systemRedColor;
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
    }
    return c;
}

- (void)modeChanged:(UISegmentedControl *)s {
    self.mode = s.selectedSegmentIndex == 1 ? @"strong" : @"normal";
    [self persist];
    [self.tableView reloadData];
}

- (void)styleChanged:(UISegmentedControl *)s {
    self.style = s.selectedSegmentIndex == 1 ? @"combo" : @"single";
    [self persist];
    [self.tableView reloadData];
}

- (void)toggle:(UISwitch *)sw {
    NSInteger i = sw.tag - 100;
    if (i == 0) self.strEnc = sw.on;
    else if (i == 1) self.intEnc = sw.on;
    else if (i == 2) self.floatEnc = sw.on;
    else if (i == 3) self.flatten = sw.on;
    [self persist];
    [self.tableView reloadData];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section != 3) return;
    if (ip.row == 0) {
        [UIPasteboard generalPasteboard].string = [self flagsString];
        [self alert:[NSString stringWithFormat:@"编译参数已复制：\n\n%@", [self flagsString]]];
    } else {
        self.mode = @"normal";
        self.style = @"combo";
        self.strEnc = self.intEnc = self.floatEnc = self.flatten = YES;
        [self persist];
        [self.tableView reloadData];
    }
}

- (void)alert:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"编译保护"
                                                             message:msg
                                                      preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
