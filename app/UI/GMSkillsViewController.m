// GM Agent · Skills 与扩展（完整 UI：指令 / Skills / MCP / 插件，均可增删改）
#import "GMSkillsViewController.h"
#import "GMLog.h"
#import "GMFilesViewController.h"

static NSString *SkillsRoot(void) {
    NSString *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    return [lib stringByAppendingPathComponent:@"Skills"];
}

static NSString *PluginsRoot(void) {
    NSString *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    return [lib stringByAppendingPathComponent:@"Plugins"];
}

static NSString *MCPPath(void) {
    NSString *doc = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *a = [doc stringByAppendingPathComponent:@"mcp.json"];
    if ([NSFileManager.defaultManager fileExistsAtPath:a]) return a;
    NSString *b = @"/var/mobile/.gm/mcp.json";
    if ([NSFileManager.defaultManager fileExistsAtPath:b]) return b;
    return a;
}

@interface GMSkillsViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSString *> *skills;
@property (nonatomic, strong) NSArray<NSDictionary *> *mcp;
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

#pragma mark - 数据

- (void)reloadAll {
    NSFileManager *fm = NSFileManager.defaultManager;

    NSString *root = SkillsRoot();
    [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
    self.skills = [[fm contentsOfDirectoryAtPath:root error:nil]
                   sortedArrayUsingSelector:@selector(compare:)] ?: @[];

    self.mcp = [self loadMCP];

    NSString *plugRoot = PluginsRoot();
    [fm createDirectoryAtPath:plugRoot withIntermediateDirectories:YES attributes:nil error:nil];
    self.plugins = [[fm contentsOfDirectoryAtPath:plugRoot error:nil]
                    sortedArrayUsingSelector:@selector(compare:)] ?: @[];

    [self.tableView reloadData];
}

- (NSArray<NSDictionary *> *)loadMCP {
    NSData *d = [NSData dataWithContentsOfFile:MCPPath()];
    if (!d) return @[];
    id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) return @[];
    id servers = obj[@"servers"];
    if (![servers isKindOfClass:[NSArray class]]) return @[];
    return servers;
}

- (void)saveMCP:(NSArray<NSDictionary *> *)servers {
    NSDictionary *root = @{@"servers": servers ?: @[]};
    NSData *d = [NSJSONSerialization dataWithJSONObject:root
                                                options:NSJSONWritingPrettyPrinted
                                                  error:nil];
    NSString *path = MCPPath();
    [d writeToFile:path atomically:YES];
    [self reloadAll];
}

#pragma mark - 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return @[@"指令", @"Skills", @"MCP 服务", @"插件"][s];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    switch (s) {
        case 0: return @"全局指令对所有会话生效；项目指令在「工作区」里单独配置。";
        case 1: return self.skills.count ? nil : @"把包含 SKILL.md 的文件夹放入 Library/Skills 即可被识别。";
        case 2: return self.mcp.count ? nil : @"在 mcp.json 中配置 servers 数组（name / command / args）。";
        case 3: return self.plugins.count ? nil : @"暂无插件。";
        default: return nil;
    }
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    switch (s) {
        case 0: return 2;
        case 1: return self.skills.count;
        case 2: return self.mcp.count + 1;   /* +1 = 添加 */
        case 3: return self.plugins.count;
        default: return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"sk";
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    c.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    c.detailTextLabel.font = [UIFont systemFontOfSize:11];

    if (ip.section == 0) {
        NSString *key = ip.row == 0 ? @"gm.globalInstruction" : @"gm.projectInstruction";
        NSString *txt = [[NSUserDefaults standardUserDefaults] stringForKey:key];
        c.textLabel.text = ip.row == 0 ? @"全局指令" : @"项目指令";
        if (txt.length) {
            NSString *flat = [txt stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
            NSString *preview = flat.length > 30 ? [flat substringToIndex:30] : flat;
            c.detailTextLabel.text = [NSString stringWithFormat:@"%lu 字符 · %@",
                                      (unsigned long)txt.length, preview];
        } else {
            c.detailTextLabel.text = @"未配置";
        }
        c.imageView.image = [UIImage systemImageNamed:ip.row == 0 ? @"text.alignleft" : @"folder.badge.gearshape"];
        c.imageView.tintColor = ip.row == 0 ? UIColor.systemBlueColor : UIColor.systemIndigoColor;
        c.imageView.contentMode = UIViewContentModeScaleAspectFit;
        c.imageView.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:18];

    } else if (ip.section == 1) {
        NSString *name = self.skills[ip.row];
        c.textLabel.text = name;
        NSString *md = [SkillsRoot() stringByAppendingPathComponent:
                        [name stringByAppendingPathComponent:@"SKILL.md"]];
        BOOL has = [NSFileManager.defaultManager fileExistsAtPath:md];
        c.detailTextLabel.text = has ? @"包含 SKILL.md · 已生效" : @"缺少 SKILL.md · 未生效";
        c.imageView.image = [UIImage systemImageNamed:has ? @"sparkles" : @"exclamationmark.triangle"];
        c.imageView.tintColor = has ? UIColor.systemPurpleColor : UIColor.systemOrangeColor;
        c.imageView.contentMode = UIViewContentModeScaleAspectFit;
        c.imageView.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:18];

    } else if (ip.section == 2) {
        if (ip.row >= self.mcp.count) {
            c.textLabel.text = @"添加 MCP 服务";
            c.textLabel.textColor = UIColor.systemBlueColor;
            c.detailTextLabel.text = @"手动填写 name / command / args";
            c.imageView.image = [UIImage systemImageNamed:@"plus.circle.fill"];
            c.imageView.tintColor = UIColor.systemBlueColor;
        } else {
            NSDictionary *s = self.mcp[ip.row];
            c.textLabel.text = s[@"name"] ?: @"未命名";
            NSString *cmd = s[@"command"] ?: @"";
            NSArray *args = s[@"args"];
            c.detailTextLabel.text = args.count
                ? [NSString stringWithFormat:@"%@ %@", cmd, [args componentsJoinedByString:@" "]]
                : cmd;
            c.imageView.image = [UIImage systemImageNamed:@"server.rack"];
            c.imageView.tintColor = UIColor.systemTealColor;
        }
        c.imageView.contentMode = UIViewContentModeScaleAspectFit;
        c.imageView.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:18];

    } else {
        NSString *name = self.plugins[ip.row];
        c.textLabel.text = name;
        c.detailTextLabel.text = @"已安装";
        c.imageView.image = [UIImage systemImageNamed:@"puzzlepiece.extension.fill"];
        c.imageView.tintColor = UIColor.systemOrangeColor;
        c.imageView.contentMode = UIViewContentModeScaleAspectFit;
        c.imageView.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:18];
    }
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) {
        [self editInstruction:ip.row == 0];
    } else if (ip.section == 1) {
        [self viewSkill:self.skills[ip.row]];
    } else if (ip.section == 2) {
        if (ip.row >= self.mcp.count) [self addMCPServer];
        else [self editMCPServer:ip.row];
    } else {
        [self viewPlugin:self.plugins[ip.row]];
    }
}

- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)style
 forRowAtIndexPath:(NSIndexPath *)ip {
    if (style != UITableViewCellEditingStyleDelete) return;
    if (ip.section == 2 && ip.row < self.mcp.count) {
        NSMutableArray *m = [self.mcp mutableCopy];
        [m removeObjectAtIndex:ip.row];
        [self saveMCP:m];
    } else if (ip.section == 1) {
        NSString *p = [SkillsRoot() stringByAppendingPathComponent:self.skills[ip.row]];
        [NSFileManager.defaultManager removeItemAtPath:p error:nil];
        [self reloadAll];
    } else if (ip.section == 3) {
        NSString *p = [PluginsRoot() stringByAppendingPathComponent:self.plugins[ip.row]];
        [NSFileManager.defaultManager removeItemAtPath:p error:nil];
        [self reloadAll];
    }
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip {
    return ip.section != 0;
}

#pragma mark - 指令编辑

- (void)editInstruction:(BOOL)global {
    NSString *key = global ? @"gm.globalInstruction" : @"gm.projectInstruction";
    NSString *cur = [[NSUserDefaults standardUserDefaults] stringForKey:key] ?: @"";

    UIAlertController *a = [UIAlertController alertControllerWithTitle:(global ? @"全局指令" : @"项目指令")
                                                            message:@"编辑后点保存生效"
                                                     preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = cur;
        tf.placeholder = @"例如：回答必须用中文，代码加注释";
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *v = a.textFields.firstObject.text ?: @"";
        [[NSUserDefaults standardUserDefaults] setObject:v forKey:key];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [self reloadAll];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Skills

- (void)viewSkill:(NSString *)name {
    NSString *dir = [SkillsRoot() stringByAppendingPathComponent:name];
    NSString *md = [dir stringByAppendingPathComponent:@"SKILL.md"];
    NSString *content = [NSString stringWithContentsOfFile:md
                                                 encoding:NSUTF8StringEncoding
                                                    error:nil];
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:name
                         message:(content.length
                                   ? (content.length > 1200 ? [content substringToIndex:1200] : content)
                                   : @"该目录缺少 SKILL.md，不会被注入提示词。")
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - MCP

- (void)addMCPServer {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"添加 MCP 服务"
                                                            message:@"填写名称与启动命令"
                                                     preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"名称，如 filesystem"; }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"命令，如 npx -y @modelcontextprotocol/server-filesystem /var/mobile";
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"添加" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *name = a.textFields[0].text ?: @"";
        NSString *cmdline = a.textFields[1].text ?: @"";
        if (!name.length || !cmdline.length) return;
        NSArray *parts = [cmdline componentsSeparatedByString:@" "];
        NSMutableArray *args = [NSMutableArray array];
        for (NSUInteger i = 1; i < parts.count; i++) {
            if ([parts[i] length]) [args addObject:parts[i]];
        }
        NSDictionary *item = @{@"name": name,
                               @"command": parts.firstObject ?: @"",
                               @"args": args};
        NSMutableArray *m = [self.mcp mutableCopy] ?: [NSMutableArray array];
        [m addObject:item];
        [self saveMCP:m];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)editMCPServer:(NSInteger)idx {
    NSDictionary *s = self.mcp[idx];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:s[@"name"]
                                                            message:nil
                                                     preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        NSMutableArray *m = [self.mcp mutableCopy];
        [m removeObjectAtIndex:idx];
        [self saveMCP:m];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    a.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, 200, 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (void)viewPlugin:(NSString *)name {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:name
                                                            message:@"该插件已安装到 Library/Plugins。"
                                                     preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
