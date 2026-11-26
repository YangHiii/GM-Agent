// GM Agent · 设置页
// 交互：填地址 → 自动拉 /models → 点"模型"选 → 填 Key → 测试 → 保存
#import "GMAIAccountViewController.h"
#import <Security/Security.h>
#import "GMLog.h"
#import "GMProviderStore.h"

static NSString *const kKCService = @"app.gm.agent";
static NSString *const kKCAccount = @"provider.apikey";

static void kcSet(NSString *v) {
    NSDictionary *q = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                        (__bridge id)kSecAttrService: kKCService,
                        (__bridge id)kSecAttrAccount: kKCAccount};
    SecItemDelete((__bridge CFDictionaryRef)q);
    if (!v.length) return;
    NSMutableDictionary *a = [q mutableCopy];
    a[(__bridge id)kSecValueData] = [v dataUsingEncoding:NSUTF8StringEncoding];
    a[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
    SecItemAdd((__bridge CFDictionaryRef)a, NULL);
}
static NSString *kcGet(void) {
    NSDictionary *q = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                        (__bridge id)kSecAttrService: kKCService,
                        (__bridge id)kSecAttrAccount: kKCAccount,
                        (__bridge id)kSecReturnData: @YES,
                        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne};
    CFTypeRef out = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &out) == errSecSuccess && out) {
        NSData *d = (__bridge_transfer NSData *)out;
        return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    }
    return @"";
}

@interface GMAIAccountViewController ()
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UITextField *modelField;
@property (nonatomic, strong) GMConversation *conversation;
@property (nonatomic, strong) UITextField *urlField;
@property (nonatomic, strong) UITextField *keyField;
@property (nonatomic, copy) NSString *model;
@property (nonatomic, strong) NSArray<NSString *> *models;
@property (nonatomic) BOOL loadingModels;
@property (nonatomic, copy) NSString *statusText;
@property (nonatomic, copy) NSString *providerIdent;
@end

@implementation GMAIAccountViewController

- (instancetype)initWithConversation:(GMConversation *)conversation {
    return [self initWithConversation:conversation providerIdent:nil];
}

- (instancetype)initWithConversation:(GMConversation *)conversation providerIdent:(NSString *)ident {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _conversation = conversation;
        _providerIdent = [ident copy];
    }
    return self;
}

- (GMProviderRecord *)currentProvider {
    if (!self.providerIdent.length) return nil;
    for (GMProviderRecord *r in [GMProviderStore shared].providers)
        if ([r.ident isEqualToString:self.providerIdent]) return r;
    return nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"AI 账号";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone
                                        target:self action:@selector(save)];

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    GMProviderRecord *prov = [self currentProvider];
    NSString *saved = prov.baseURL.length ? prov.baseURL : [d stringForKey:@"gm.baseURL"];
    if (prov.name.length) self.title = prov.name;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.tableView];

    self.urlField = [self makeField:@"https://api.deepseek.com/v1" secure:NO];
    self.urlField.text = saved ?: @"";
    self.urlField.keyboardType = UIKeyboardTypeURL;
    [self.urlField addTarget:self action:@selector(urlChanged) forControlEvents:UIControlEventEditingDidEnd];

    self.keyField = [self makeField:@"sk-…" secure:YES];
    self.keyField.text = prov.apiKey.length ? prov.apiKey : kcGet();
    // 键盘上浮板：粘贴按钮，方便直接贴 key
    UIToolbar *bar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    bar.items = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil],
        [[UIBarButtonItem alloc] initWithTitle:@"粘贴" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(pasteKey)],
        [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone
                                        target:self action:@selector(dismissKeyboard)],
    ];
    [bar sizeToFit];
    self.keyField.inputAccessoryView = bar;
    self.urlField.inputAccessoryView = bar;
    [self.keyField addTarget:self action:@selector(keyChanged) forControlEvents:UIControlEventEditingDidEnd];

    [NSNotificationCenter.defaultCenter addObserver:self
                                          selector:@selector(keyboardFrameChanged:)
                                              name:UIKeyboardWillChangeFrameNotification
                                            object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                          selector:@selector(keyboardFrameChanged:)
                                              name:UIKeyboardWillShowNotification
                                            object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                          selector:@selector(keyboardFrameChanged:)
                                              name:UIKeyboardWillHideNotification
                                            object:nil];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.tableView addGestureRecognizer:tap];

    self.model = prov.model.length ? prov.model : ([d stringForKey:@"gm.model"] ?: @"");
    self.models = @[];
    if (self.urlField.text.length && self.model.length) {
        [self fetchModelsQuietly];
    }
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

- (void)keyboardFrameChanged:(NSNotification *)note {
    NSDictionary *info = note.userInfo;
    CGRect end = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    NSTimeInterval dur = [info[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    CGRect inView = [self.view convertRect:end fromView:nil];
    CGFloat overlap = CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(inView);
    CGFloat inset = MAX(0, overlap - self.view.safeAreaInsets.bottom);
    UIEdgeInsets ei = self.tableView.contentInset;
    ei.bottom = inset + 8;
    self.tableView.contentInset = ei;
    self.tableView.scrollIndicatorInsets = ei;
    if (dur <= 0) dur = 0.25;
    [UIView animateWithDuration:dur animations:^{
        [self.view layoutIfNeeded];
    }];
    // 让当前聚焦的输入框可见
    UIView *first = [self findFirstResponder:self.view];
    if (first) {
        UITableViewCell *cell = (UITableViewCell *)first.superview.superview;
        if ([cell isKindOfClass:[UITableViewCell class]]) {
            NSIndexPath *ip = [self.tableView indexPathForCell:cell];
            if (ip) [self.tableView scrollToRowAtIndexPath:ip
                                          atScrollPosition:UITableViewScrollPositionMiddle
                                                  animated:YES];
        }
    }
}

- (UIView *)findFirstResponder:(UIView *)v {
    if (v.isFirstResponder) return v;
    for (UIView *sub in v.subviews) {
        UIView *r = [self findFirstResponder:sub];
        if (r) return r;
    }
    return nil;
}

- (UITextField *)makeField:(NSString *)ph secure:(BOOL)secure {
    UITextField *f = [UITextField new];
    f.placeholder = ph;
    f.secureTextEntry = secure;
    f.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.spellCheckingType = UITextSpellCheckingTypeNo;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.returnKeyType = UIReturnKeyDone;
    f.delegate = self;
    f.translatesAutoresizingMaskIntoConstraints = NO;
    return f;
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    [tf resignFirstResponder];
    return YES;
}

// ---- 地址归一化：用户可能只填 host 或 /v1 或完整 /chat/completions ----
- (NSString *)normalizedBase {
    NSString *s = [self.urlField.text stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!s.length) return @"";
    if (![s.lowercaseString hasPrefix:@"http://"] && ![s.lowercaseString hasPrefix:@"https://"]) {
        s = [@"https://" stringByAppendingString:s];
    }
    while ([s hasSuffix:@"/"]) s = [s substringToIndex:s.length - 1];
    if ([s hasSuffix:@"/chat/completions"]) {
        s = [s substringToIndex:s.length - @"/chat/completions".length];
    }
    return s;
}

- (NSString *)chatURL {
    NSString *b = [self normalizedBase];
    if (!b.length) return @"";
    return [b stringByAppendingString:@"/chat/completions"];
}

- (NSString *)modelsURL {
    NSString *b = [self normalizedBase];
    if (!b.length) return @"";
    return [b stringByAppendingString:@"/models"];
}

- (void)pasteKey {
    NSString *s = [UIPasteboard generalPasteboard].string;
    if (s.length) {
        self.keyField.text = [s stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (self.models.count == 0) [self fetchModelsQuietly];
    }
}

- (void)urlChanged {
    [self fetchModelsQuietly];
}

- (void)keyChanged {
    if (self.models.count == 0) [self fetchModelsQuietly];
}

- (void)fetchModelsQuietly {
    self.loadingModels = YES;
    self.statusText = @"正在获取模型列表…";
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2]
                  withRowAnimation:UITableViewRowAnimationNone];

    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[self modelsURL]]];
    r.HTTPMethod = @"GET";
    r.timeoutInterval = 20;
    NSString *key = self.keyField.text.length ? self.keyField.text : kcGet();
    if (key.length) [r setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    [r setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    __weak typeof(self) wself = self;
    [[[NSURLSession sharedSession] dataTaskWithRequest:r
                                    completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) s = wself;
            if (!s) return;
            s.loadingModels = NO;
            NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
            if (err) {
                s.statusText = [NSString stringWithFormat:@"获取失败：%@", err.localizedDescription];
            } else if (code == 401 || code == 403) {
                s.statusText = @"获取失败：Key 无效（可先填 Key 再获取）";
            } else if (code >= 400) {
                s.statusText = [NSString stringWithFormat:@"获取失败：HTTP %ld", (long)code];
            } else {
                id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
                NSMutableArray *ids = [NSMutableArray array];
                if ([obj isKindOfClass:[NSDictionary class]] && [obj[@"data"] isKindOfClass:[NSArray class]]) {
                    for (id m in obj[@"data"]) {
                        NSString *ident = nil;
                        if ([m isKindOfClass:[NSDictionary class]]) {
                            ident = m[@"id"] ?: m[@"name"];
                        } else if ([m isKindOfClass:[NSString class]]) {
                            ident = m;
                        }
                        if (ident.length) [ids addObject:ident];
                    }
                } else if ([obj isKindOfClass:[NSArray class]]) {
                    for (id m in obj) {
                        if ([m isKindOfClass:[NSDictionary class]] && m[@"id"]) [ids addObject:m[@"id"]];
                        else if ([m isKindOfClass:[NSString class]]) [ids addObject:m];
                    }
                }
                s.models = [ids sortedArrayUsingSelector:@selector(compare:)];
                if (s.models.count) {
                    s.statusText = [NSString stringWithFormat:@"已获取 %lu 个模型", (unsigned long)s.models.count];
                    if (!s.model.length || ![s.models containsObject:s.model]) s.model = s.models.firstObject;
                } else {
                    s.statusText = @"未获取到模型（可手动输入模型名）";
                }
            }
            [s.tableView reloadSections:[NSIndexSet indexSetWithIndex:2]
                       withRowAnimation:UITableViewRowAnimationNone];
            [s.tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
                       withRowAnimation:UITableViewRowAnimationNone];
        });
    }] resume];
}

- (void)pickModel {
    if (self.loadingModels) return;
    if (self.models.count == 0) {
        [self fetchModelsQuietly];
        [self alert:@"正在获取模型列表，稍后再点一次"];
        return;
    }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"选择模型"
                                                             message:nil
                                                      preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *m in self.models) {
        [a addAction:[UIAlertAction actionWithTitle:m style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            self.model = m;
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
                          withRowAnimation:UITableViewRowAnimationNone];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"手动输入" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self manualModel];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    a.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, 200, 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (void)manualModel {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"模型名"
                                                             message:@"例如 deepseek-chat"
                                                      preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = self.model;
        tf.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        self.model = a.textFields.firstObject.text ?: @"";
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
                      withRowAnimation:UITableViewRowAnimationNone];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 5; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return @[@"连接", @"模型", @"状态", @"操作", @"诊断"][s];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) return @"地址填到 /v1 即可（如 https://api.deepseek.com/v1），会自动补 /chat/completions";
    if (s == 1) return @"点这一行选择模型；列表会自动从服务端 /models 获取";
    return nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 2;      // 地址 + Key（都在顶部，键盘挡不到）
    if (s == 4) return 2;      // 查看日志 / 复制路径
    return 1;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    return 48;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"cell";
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cid];
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    c.accessoryView = nil;
    c.accessoryType = UITableViewCellAccessoryNone;
    c.detailTextLabel.text = nil;
    c.textLabel.textColor = UIColor.labelColor;

    if (ip.row >= [tv numberOfRowsInSection:ip.section]) return c;

    if (ip.section == 0) {
        if (ip.row == 0) {
            c.textLabel.text = @"地址";
            [self attachField:self.urlField toCell:c];
        } else {
            c.textLabel.text = @"API Key";
            [self attachField:self.keyField toCell:c];
        }
    } else if (ip.section == 1) {
        c.textLabel.text = @"模型";
        c.detailTextLabel.text = self.model.length ? self.model : @"未选择";
        c.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        c.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else if (ip.section == 2) {
        c.textLabel.text = self.statusText.length ? self.statusText : @"未检测";
        c.textLabel.font = [UIFont systemFontOfSize:13];
        c.textLabel.numberOfLines = 0;
        c.textLabel.textColor = [self.statusText hasPrefix:@"已获取"] ? UIColor.systemGreenColor :
                                ([self.statusText hasPrefix:@"获取失败"] || [self.statusText hasPrefix:@"未获取"]
                                 ? UIColor.systemOrangeColor : UIColor.secondaryLabelColor);
    } else if (ip.section == 3) {
        c.textLabel.text = @"测试连接";
        c.textLabel.textColor = UIColor.systemBlueColor;
        c.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else {
        c.textLabel.text = ip.row == 0 ? @"查看启动日志" : @"复制日志路径";
        c.textLabel.textColor = UIColor.systemBlueColor;
        c.selectionStyle = UITableViewCellSelectionStyleDefault;
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return c;
}

// 关键：把输入框放进 contentView 并约束，避免被裁切/遮挡
- (void)attachField:(UITextField *)field toCell:(UITableViewCell *)cell {
    if (field.superview == cell.contentView) return;
    [field.superview removeConstraints:field.constraints];
    [NSLayoutConstraint deactivateConstraints:field.constraints];
    [field removeFromSuperview];
    [cell.contentView addSubview:field];
    [NSLayoutConstraint activateConstraints:@[
        [field.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:86],
        [field.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
        [field.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [field.heightAnchor constraintEqualToConstant:34],
    ]];
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 1) {
        [self.view endEditing:YES];
        [self pickModel];
    } else if (ip.section == 3) {
        [self.view endEditing:YES];
        [self testConnection];
    } else if (ip.section == 4) {
        if (ip.row == 0) {
            [self showLog];
        } else {
            [UIPasteboard generalPasteboard].string = GMLogPath();
            [self alert:[NSString stringWithFormat:@"路径已复制：\n%@", GMLogPath()]];
        }
    }
}

- (void)testConnection {
    if (![self chatURL].length) { [self alert:@"请先填网关地址"]; return; }
    NSString *key = self.keyField.text.length ? self.keyField.text : kcGet();
    if (!key.length) { [self alert:@"请先填 API Key"]; return; }
    if (!self.model.length) { [self alert:@"请先选择模型"]; return; }

    self.statusText = @"测试中…";
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2]
                  withRowAnimation:UITableViewRowAnimationNone];

    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    body[@"model"] = self.model;
    body[@"messages"] = @[@{@"role": @"user", @"content": @"ping"}];
    body[@"max_tokens"] = @16;
    body[@"stream"] = @NO;

    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[self chatURL]]];
    r.HTTPMethod = @"POST";
    r.timeoutInterval = 40;
    [r setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    r.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];

    __weak typeof(self) wself = self;
    [[[NSURLSession sharedSession] dataTaskWithRequest:r
                                    completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) s = wself;
            if (!s) return;
            NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
            if (err) {
                s.statusText = [NSString stringWithFormat:@"测试失败：%@", err.localizedDescription];
                [s.tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationNone];
                return;
            }
            if (code >= 200 && code < 300) {
                s.statusText = [NSString stringWithFormat:@"✅ 连接成功（%ld）· %@", (long)code, s.model];
                [s.tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationNone];
            } else {
                NSString *t = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
                if (t.length > 160) t = [t substringToIndex:160];
                s.statusText = [NSString stringWithFormat:@"❌ HTTP %ld", (long)code];
                [s.tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationNone];
                [s alert:[NSString stringWithFormat:@"HTTP %ld\n\n%@", (long)code, t]];
            }
        });
    }] resume];
}

- (void)save {
    [self.view endEditing:YES];
    NSString *url = [self normalizedBase];
    NSString *key = self.keyField.text ?: @"";
    if (!url.length) { [self alert:@"请填写网关地址"]; return; }
    if (![url.lowercaseString hasPrefix:@"http"]) { [self alert:@"地址需以 http:// 或 https:// 开头"]; return; }
    if (!key.length) { [self alert:@"请填写 API Key"]; return; }
    if (!self.model.length) { [self alert:@"请选择模型"]; return; }

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:[self chatURL] forKey:@"gm.baseURL"];
    [d setObject:url forKey:@"gm.baseRoot"];
    [d setObject:self.model forKey:@"gm.model"];
    /* 写回供应商存储（多供应商模式） */
    GMProviderRecord *prov = [self currentProvider];
    if (prov) {
        prov.baseURL = [self chatURL];
        prov.apiKey = key;
        prov.model = self.model;
        if (!prov.name.length) {
            NSURL *u = [NSURL URLWithString:prov.baseURL];
            if (u.host.length) prov.name = u.host;
        }
        prov.active = YES;
        prov.modelsJSON = self.models.count ? ({
            NSData *dd = [NSJSONSerialization dataWithJSONObject:self.models options:0 error:nil];
            [[NSString alloc] initWithData:dd encoding:NSUTF8StringEncoding];
        }) : @"[]";
        [[GMProviderStore shared] updateProvider:prov];
        [[GMProviderStore shared] activateProvider:prov.ident];
    } else {
        [d setObject:key forKey:@"gm.apiKey"];
        {
            NSURL *u = [NSURL URLWithString:[self chatURL]];
            if (u.host.length) [d setObject:u.host forKey:@"gm.providerName"];
        }
        [d synchronize];
        kcSet(key);
    }

    self.conversation.model = self.model;
    [self.conversation pushConfigToEngine];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)showLog {
    NSString *content = [NSString stringWithContentsOfFile:GMLogPath()
                                                 encoding:NSUTF8StringEncoding error:nil];
    if (!content.length) content = @"(日志为空或文件不存在)";
    UIViewController *vc = [UIViewController new];
    vc.title = @"启动日志";
    vc.view.backgroundColor = UIColor.systemBackgroundColor;
    UITextView *tv = [[UITextView alloc] initWithFrame:vc.view.bounds];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.editable = NO;
    tv.text = content;
    tv.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    [vc.view addSubview:tv];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)alert:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"GM Agent"
                                                              message:msg
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
