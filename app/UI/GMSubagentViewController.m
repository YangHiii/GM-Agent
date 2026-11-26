// GM Agent · 子代理设置：模型 / 思考强度
#import "GMSubagentViewController.h"

@interface GMSubagentViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSString *modelMode;     // follow | custom
@property (nonatomic, copy) NSString *model;
@property (nonatomic, copy) NSString *effortMode;    // follow | custom
@property (nonatomic, copy) NSString *effort;
@end

@implementation GMSubagentViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"子代理";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    self.modelMode = [d stringForKey:@"gm.subagent.modelMode"] ?: @"follow";
    self.model = [d stringForKey:@"gm.subagent.model"] ?: @"";
    self.effortMode = [d stringForKey:@"gm.subagent.effortMode"] ?: @"follow";
    self.effort = [d stringForKey:@"gm.subagent.effort"] ?: @"medium";

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
}

- (void)persist {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:self.modelMode forKey:@"gm.subagent.modelMode"];
    [d setObject:self.model ?: @"" forKey:@"gm.subagent.model"];
    [d setObject:self.effortMode forKey:@"gm.subagent.effortMode"];
    [d setObject:self.effort forKey:@"gm.subagent.effort"];
    [d synchronize];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return @[@"默认行为", @"", @""][s];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) return @"子代理用于并行探索与检索。设为「跟随主代理」时使用主对话的模型与思考强度。";
    return nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 1;                                    // 模型
    if (s == 1) return 1;                                    // 思考强度
    return 1;                                                // 恢复默认
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"c";
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cid];

    if (ip.section == 0) {
        c.textLabel.text = @"模型";
        c.textLabel.textColor = UIColor.labelColor;
        if ([self.modelMode isEqualToString:@"follow"]) {
            NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
            NSString *main = [d stringForKey:@"gm.model"] ?: @"未设置";
            c.detailTextLabel.text = [NSString stringWithFormat:@"跟随 · %@", main];
            c.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        } else {
            c.detailTextLabel.text = self.model.length ? self.model : @"未指定";
            c.detailTextLabel.textColor = UIColor.labelColor;
        }
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (ip.section == 1) {
        c.textLabel.text = @"思考强度";
        c.textLabel.textColor = UIColor.labelColor;
        c.detailTextLabel.text = [self.effortMode isEqualToString:@"follow"]
            ? @"跟随主代理" : [self effortDisplay:self.effort];
        c.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        c.textLabel.text = @"恢复跟随主代理";
        c.textLabel.textColor = UIColor.systemRedColor;
        c.detailTextLabel.text = nil;
        c.accessoryType = UITableViewCellAccessoryNone;
    }
    return c;
}

- (NSString *)effortDisplay:(NSString *)e {
    if ([e isEqualToString:@"low"]) return @"低";
    if ([e isEqualToString:@"high"]) return @"高";
    return @"中";
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];

    if (ip.section == 2) {
        self.modelMode = @"follow";
        self.effortMode = @"follow";
        self.model = @"";
        [self persist];
        [tv reloadData];
        return;
    }

    if (ip.section == 0) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"子代理模型"
                                                                 message:nil
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        NSString *main = [d stringForKey:@"gm.model"] ?: @"";
        [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"跟随主代理（%@）", main]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *x) {
            self.modelMode = @"follow";
            [self persist];
            [tv reloadData];
        }]];
        [a addAction:[UIAlertAction actionWithTitle:@"指定其他模型" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *x) {
            [self askModel];
        }]];
        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        a.popoverPresentationController.sourceView = self.view;
        a.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, 200, 1, 1);
        [self presentViewController:a animated:YES completion:nil];
    } else if (ip.section == 1) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"思考强度"
                                                                 message:nil
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
        [a addAction:[UIAlertAction actionWithTitle:@"跟随主代理" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *x) {
            self.effortMode = @"follow";
            [self persist];
            [tv reloadData];
        }]];
        for (NSString *e in @[@"low", @"medium", @"high"]) {
            [a addAction:[UIAlertAction actionWithTitle:[self effortDisplay:e]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *x) {
                self.effortMode = @"custom";
                self.effort = e;
                [self persist];
                [tv reloadData];
            }]];
        }
        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        a.popoverPresentationController.sourceView = self.view;
        a.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, 200, 1, 1);
        [self presentViewController:a animated:YES completion:nil];
    }
}

- (void)askModel {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"模型名"
                                                            message:@"例如 deepseek-chat / gpt-5.2"
                                                     preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = self.model;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *m = a.textFields.firstObject.text;
        if (m.length) {
            self.modelMode = @"custom";
            self.model = m;
            [self persist];
            [self.tableView reloadData];
        }
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
