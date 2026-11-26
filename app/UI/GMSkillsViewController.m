// GM Agent · Skills 与扩展：全局指令（真实生效）/ 项目指令 / Skills / MCP / 插件
#import "GMSkillsViewController.h"
#import "GMLog.h"

static NSString *SkillsRoot(void) {
    NSString *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    return [lib stringByAppendingPathComponent:@"Skills"];
}

@interface GMSkillsViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSString *> *skills;
@property (nonatomic, strong) NSArray<NSString *> *mcp;
@property (nonatomic, strong) NSArray<NSString *> *plugins;
@property (nonatomic, copy) NSString *editingKey;
@property (nonatomic, strong) UITextView *editingView;
@end

@implementation GMSkillsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Skills 与扩展";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
    [self reloadAll];
}

- (void)reloadAll {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *root = SkillsRoot();
    [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    self.skills = [[fm contentsOfDirectoryAtPath:root error:nil] sortedArrayUsingSelector:@selector(compare:)];

    /* MCP 配置：优先 App 容器，其次 /var/mobile */
    NSString *mcpPath = nil;
    NSArray *cands = @[@"/var/mobile/.gm/mcp.json",
                       [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
                        stringByAppendingPathComponent:@"mcp.json"]];
    for (NSString *p in cands) {
        if ([fm fileExistsAtPath:p]) { mcpPath = p; break; }
    }
    id mc = nil;
    if (mcpPath) {
        NSData *d = [NSData dataWithContentsOfFile:mcpPath];
        if (d) mc = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    }
    NSArray *servers = [mc isKindOfClass:[NSDictionary class]] ? mc[@"servers"] : nil;
    self.mcp = [servers isKindOfClass:[NSArray class]] ? servers : @[];

    NSString *plugRoot = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject
                          stringByAppendingPathComponent:@"Plugins"];
    [fm createDirectoryAtPath:plugRoot withIntermediateDirectories:YES attributes:nil error:nil];
    self.plugins = [[fm contentsOfDirectoryAtPath:plugRoot error:nil] sortedArrayUsingSelector:@selector(compare:)];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return @[@"指令", @"Skills", @"MCP 服务", @"插件"][s];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) return @"全局指令会随每次请求发送给模型，相当于额外的系统提示。";
    if (s == 1) return [NSString stringWithFormat:@"目录：%@\n放一个 <名称>/SKILL.md 即被识别。", SkillsRoot()];
    return nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 2;   // 全局指令 / 项目指令
    if (s == 1) return self.skills.count;
    if (s == 2) return self.mcp.count;
    return self.plugins.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"c";
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    c.textLabel.textColor = UIColor.labelColor;
    c.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    c.detailTextLabel.font = [UIFont systemFontOfSize:11];
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    if (ip.section == 0) {
        if (ip.row == 0) {
            NSString *g = [[NSUserDefaults standardUserDefaults] stringForKey:@"gm.globalInstruction"];
            c.textLabel.text = @"全局指令";
            c.detailTextLabel.text = g.length
                ? [NSString stringWithFormat:@"已配置 %lu 字", (unsigned long)g.length]
                : @"未配置";
        } else {
            c.textLabel.text = @"项目指令";
            c.detailTextLabel.text = @"按工作区分别配置";
        }
    } else if (ip.section == 1) {
        if (ip.row >= self.skills.count) return c;
        c.textLabel.text = self.skills[ip.row];
        NSString *md = [SkillsRoot() stringByAppendingPathComponent:
                        [self.skills[ip.row] stringByAppendingPathComponent:@"SKILL.md"]];
        c.detailTextLabel.text = [NSFileManager.defaultManager fileExistsAtPath:md] ? @"SKILL.md ✓" : @"缺少 SKILL.md";
    } else if (ip.section == 2) {
        if (ip.row >= self.mcp.count) return c;
        c.textLabel.text = self.mcp[ip.row];
        c.detailTextLabel.text = @"已配置（MCP 协议客户端将在后续版本接入）";
        c.detailTextLabel.font = [UIFont systemFontOfSize:10];
    } else {
        if (ip.row >= self.plugins.count) return c;
        c.textLabel.text = self.plugins[ip.row];
        c.accessoryType = UITableViewCellAccessoryNone;
    }
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) {
        [self editInstruction:ip.row == 0];
    } else if (ip.section == 1) {
        if (ip.row < self.skills.count) [self showSkill:self.skills[ip.row]];
    } else {
        [self alert:@"该扩展暂未启用"];
    }
}

- (void)editInstruction:(BOOL)global {
    self.editingKey = global ? @"gm.globalInstruction" : @"gm.projectInstruction";

    UIViewController *vc = [UIViewController new];
    vc.title = global ? @"全局指令" : @"项目指令";
    vc.view.backgroundColor = UIColor.systemBackgroundColor;

    UITextView *tv = [[UITextView alloc] initWithFrame:vc.view.bounds];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    tv.text = [[NSUserDefaults standardUserDefaults] stringForKey:self.editingKey] ?: @"";
    self.editingView = tv;
    [vc.view addSubview:tv];

    vc.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone
                                        target:self action:@selector(saveInstruction)];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)saveInstruction {
    if (self.editingKey && self.editingView) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d setObject:self.editingView.text ?: @"" forKey:self.editingKey];
        [d synchronize];
        GMLog(@"保存指令 %@ (%lu 字)", self.editingKey, (unsigned long)self.editingView.text.length);
    }
    [self reloadAll];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)showSkill:(NSString *)name {
    NSString *md = [SkillsRoot() stringByAppendingPathComponent:[name stringByAppendingPathComponent:@"SKILL.md"]];
    NSString *content = [NSString stringWithContentsOfFile:md encoding:NSUTF8StringEncoding error:nil];
    if (!content.length) content = @"(缺少 SKILL.md)";
    UIViewController *vc = [UIViewController new];
    vc.title = name;
    vc.view.backgroundColor = UIColor.systemBackgroundColor;
    UITextView *tv = [[UITextView alloc] initWithFrame:vc.view.bounds];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.editable = NO;
    tv.text = content;
    tv.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    [vc.view addSubview:tv];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)alert:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Skills 与扩展"
                                                             message:msg
                                                      preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
