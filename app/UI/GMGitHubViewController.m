// GM Agent · GitHub 账号：保存 PAT，真实调用 api.github.com 校验
#import "GMGitHubViewController.h"
#import <Security/Security.h>
#import "GMLog.h"

static NSString *const kSvc = @"app.gm.agent.github";
static NSString *const kAcc = @"pat";

static void patSet(NSString *v) {
    NSDictionary *q = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                        (__bridge id)kSecAttrService: kSvc,
                        (__bridge id)kSecAttrAccount: kAcc};
    SecItemDelete((__bridge CFDictionaryRef)q);
    if (!v.length) return;
    NSMutableDictionary *a = [q mutableCopy];
    a[(__bridge id)kSecValueData] = [v dataUsingEncoding:NSUTF8StringEncoding];
    a[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
    SecItemAdd((__bridge CFDictionaryRef)a, NULL);
}
static NSString *patGet(void) {
    NSDictionary *q = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                        (__bridge id)kSecAttrService: kSvc,
                        (__bridge id)kSecAttrAccount: kAcc,
                        (__bridge id)kSecReturnData: @YES,
                        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne};
    CFTypeRef out = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &out) == errSecSuccess && out) {
        NSData *d = (__bridge_transfer NSData *)out;
        return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    }
    return @"";
}

@interface GMGitHubViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITextField *userField;
@property (nonatomic, strong) UITextField *patField;
@property (nonatomic, copy) NSString *status;      // 状态文案
@property (nonatomic, copy) NSString *loginName;
@end

@implementation GMGitHubViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"GitHub 账号";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    self.loginName = [d stringForKey:@"gm.github.login"];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.tableView];

    self.userField = [self field:@"用户名" secure:NO];
    self.userField.text = self.loginName;
    self.patField = [self field:@"github_pat_… 或 ghp_…" secure:YES];
    self.patField.text = patGet();

    if (self.loginName.length) {
        self.status = [NSString stringWithFormat:@"已连接 %@", self.loginName];
    }
}

- (UITextField *)field:(NSString *)ph secure:(BOOL)secure {
    UITextField *f = [UITextField new];
    f.placeholder = ph;
    f.secureTextEntry = secure;
    f.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.spellCheckingType = UITextSpellCheckingTypeNo;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.delegate = self;
    f.translatesAutoresizingMaskIntoConstraints = NO;
    return f;
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return @[@"账号状态", @"账号信息", @"操作", @""][s];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 1;
    if (s == 1) return 2;
    return s == 2 ? 3 : 1;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"c";
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cid];
    c.accessoryView = nil;
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    c.textLabel.textColor = UIColor.labelColor;
    c.detailTextLabel.text = nil;

    if (ip.section == 0) {
        BOOL on = self.loginName.length > 0;
        c.textLabel.text = self.status.length ? self.status : (on ? @"已连接" : @"未连接");
        c.textLabel.textColor = on ? UIColor.systemGreenColor : UIColor.secondaryLabelColor;
    } else if (ip.section == 1) {
        if (ip.row == 0) {
            c.textLabel.text = @"用户名";
            [self attach:self.userField toCell:c];
        } else {
            c.textLabel.text = @"访问令牌";
            [self attach:self.patField toCell:c];
        }
    } else if (ip.section == 2) {
        if (ip.row == 0) {
            c.textLabel.text = @"验证并保存账号";
            c.textLabel.textColor = UIColor.whiteColor;
            c.backgroundColor = UIColor.systemBlueColor;
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
            c.textLabel.textAlignment = NSTextAlignmentCenter;
        } else if (ip.row == 1) {
            c.textLabel.text = @"创建访问令牌";
            c.textLabel.textColor = UIColor.systemBlueColor;
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else {
            c.textLabel.text = @"断开 GitHub 账号";
            c.textLabel.textColor = UIColor.systemRedColor;
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
    } else {
        c.textLabel.text = @"令牌保存在系统 Keychain；仅用于 git 操作，不会上传。";
        c.textLabel.font = [UIFont systemFontOfSize:12];
        c.textLabel.textColor = UIColor.secondaryLabelColor;
        c.textLabel.numberOfLines = 0;
    }
    return c;
}

- (void)attach:(UITextField *)f toCell:(UITableViewCell *)c {
    if (f.superview == c.contentView) return;
    [f removeFromSuperview];
    [c.contentView addSubview:f];
    [NSLayoutConstraint activateConstraints:@[
        [f.leadingAnchor constraintEqualToAnchor:c.contentView.leadingAnchor constant:96],
        [f.trailingAnchor constraintEqualToAnchor:c.contentView.trailingAnchor constant:-16],
        [f.centerYAnchor constraintEqualToAnchor:c.contentView.centerYAnchor],
        [f.heightAnchor constraintEqualToConstant:32],
    ]];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section != 2) return;

    if (ip.row == 0) {
        [self.view endEditing:YES];
        [self verify];
    } else if (ip.row == 1) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/settings/tokens"]
                                           options:@{} completionHandler:nil];
    } else {
        patSet(@"");
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d removeObjectForKey:@"gm.github.login"];
        [d synchronize];
        self.loginName = nil;
        self.status = @"已断开";
        self.userField.text = @"";
        self.patField.text = @"";
        [tv reloadData];
    }
}

- (void)verify {
    NSString *pat = self.patField.text ?: @"";
    if (!pat.length) { [self alert:@"请先填写访问令牌"]; return; }
    self.status = @"验证中…";
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                  withRowAnimation:UITableViewRowAnimationNone];

    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.github.com/user"]];
    r.timeoutInterval = 25;
    [r setValue:[@"Bearer " stringByAppendingString:pat] forHTTPHeaderField:@"Authorization"];
    [r setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [r setValue:@"gm-agent" forHTTPHeaderField:@"User-Agent"];

    __weak typeof(self) wself = self;
    [[[NSURLSession sharedSession] dataTaskWithRequest:r
                                    completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) s = wself;
            if (!s) return;
            NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
            if (err) {
                s.status = [NSString stringWithFormat:@"验证失败：%@", err.localizedDescription];
                [s.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
                return;
            }
            if (code != 200) {
                s.status = [NSString stringWithFormat:@"验证失败：HTTP %ld（令牌无效或权限不足）", (long)code];
                [s.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
                return;
            }
            id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSString *login = [obj isKindOfClass:[NSDictionary class]] ? obj[@"login"] : nil;
            if (!login.length) login = s.userField.text ?: @"已连接";

            patSet(pat);
            NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
            [d setObject:login forKey:@"gm.github.login"];
            [d synchronize];
            s.loginName = login;
            s.userField.text = login;
            s.status = [NSString stringWithFormat:@"已连接 %@", login];
            GMLog(@"GitHub 已连接: %@", login);
            [s.tableView reloadData];
            [s alert:[NSString stringWithFormat:@"✅ 已连接 GitHub\n\n账号：%@", login]];
        });
    }] resume];
}

- (void)alert:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"GitHub"
                                                             message:msg
                                                      preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
