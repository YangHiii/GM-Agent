// GM Agent · 子代理设置：模型 / 思考强度
#import "GMSubagentViewController.h"
#import "GMBridge.h"
#import "GMPlanViewController.h"

@interface GMSubagentViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSString *modelMode;     // follow | custom
@property (nonatomic, copy) NSString *model;
@property (nonatomic, copy) NSString *effortMode;    // follow | custom
@property (nonatomic, copy) NSString *effort;
@property (nonatomic, copy) NSString *lastOutput;
@property (nonatomic, strong) GMPlanProgressViewController *planVC;
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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return @[@"默认行为", @"", @"", @"立即执行"][s];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) return @"子代理用于并行探索与检索。设为「跟随主代理」时使用主对话的模型与思考强度。";
    return nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 1;
    if (s == 1) return 1;
    if (s == 2) return 1;
    return 2;   // 发起任务 / 最近结果
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
    } else if (ip.section == 2) {
        c.textLabel.text = @"恢复跟随主代理";
        c.textLabel.textColor = UIColor.systemRedColor;
        c.detailTextLabel.text = nil;
        c.accessoryType = UITableViewCellAccessoryNone;
    } else {
        if (ip.row == 0) {
            c.textLabel.text = @"发起子代理任务";
            c.textLabel.textColor = UIColor.systemBlueColor;
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            c.textLabel.text = @"查看最近结果";
            c.detailTextLabel.text = self.lastOutput.length ? @"有结果" : @"无";
            c.detailTextLabel.font = [UIFont systemFontOfSize:11];
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
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

    if (ip.section == 3) {
        if (ip.row == 0) [self startTask];
        else [self showLastOutput];
        return;
    }
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

- (void)startTask {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"子代理任务"
                                                            message:@"描述要让它探索/检索的内容"
                                                     preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"例如：统计当前工作区有多少个 .m 文件";
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"开始" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *task = a.textFields.firstObject.text;
        if (!task.length) return;
        /* 打开计划进度视图 */
        GMPlanStep *s1 = [GMPlanStep new];
        s1.title = @"分析任务"; s1.state = 1;
        GMPlanStep *s2 = [GMPlanStep new];
        s2.title = @"执行检索"; s2.state = 0;
        GMPlanStep *s3 = [GMPlanStep new];
        s3.title = @"汇总结果"; s3.state = 0;
        GMPlanProgressViewController *pv =
            [[GMPlanProgressViewController alloc] initWithTask:task steps:@[s1, s2, s3]];
        self.planVC = pv;
        [self.navigationController pushViewController:pv animated:YES];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(subagentEvent:)
                                                     name:@"gm.subagent" object:nil];
        [[GMBridge shared] call:@"gm/subagent/run"
                         params:@{@"task": task, @"model": [self modelMode].length ? self.model : @""}
                          reply:^(id r, NSError *e) {
            if (e) dispatch_async(dispatch_get_main_queue(), ^{
                [self alert:[NSString stringWithFormat:@"启动失败：%@", e.localizedDescription]];
            });
        }];
        [self alert:@"子代理已启动，完成后会提示。"];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)subagentEvent:(NSNotification *)note {
    NSDictionary *p = note.userInfo;
    NSString *phase = p[@"phase"];
    if ([phase isEqualToString:@"done"]) {
        self.lastOutput = p[@"output"];
        [self.tableView reloadData];
        /* 更新计划：全部完成 */
        if (self.planVC) {
            NSMutableArray *steps = [NSMutableArray array];
            for (NSString *t in @[@"分析任务", @"执行检索", @"汇总结果"]) {
                GMPlanStep *st = [GMPlanStep new];
                st.title = t; st.state = 2;
                [steps addObject:st];
            }
            [self.planVC updateSteps:steps];
        }
        /* 展示结果页 */
        GMPlanDecisionViewController *dv =
            [[GMPlanDecisionViewController alloc] initWithTask:p[@"task"] output:p[@"output"]];
        [self.navigationController pushViewController:dv animated:YES];
    } else if ([phase isEqualToString:@"error"]) {
        [self alert:[NSString stringWithFormat:@"子代理失败：%@", p[@"message"] ?: @""]];
    }
}

- (void)showLastOutput {
    if (!self.lastOutput.length) { [self alert:@"还没有结果"]; return; }
    UIViewController *vc = [UIViewController new];
    vc.title = @"子代理结果";
    vc.view.backgroundColor = UIColor.systemBackgroundColor;
    UITextView *tv = [[UITextView alloc] initWithFrame:vc.view.bounds];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.editable = NO;
    tv.text = self.lastOutput;
    tv.font = [UIFont systemFontOfSize:13];
    [vc.view addSubview:tv];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)alert:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"子代理"
                                                             message:msg
                                                      preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
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
