// GM Agent · 设置页：供应商选择 + 模型下拉 + API Key
#import "GMSettingsViewController.h"
#import "GMProviders.h"
#import <Security/Security.h>

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

@interface GMSettingsViewController ()
@property (nonatomic, strong) GMConversation *conversation;
@property (nonatomic, strong) NSArray<GMProviderPreset *> *presets;
@property (nonatomic) NSInteger presetIndex;
@property (nonatomic) NSInteger modelIndex;
@property (nonatomic, copy) NSString *customURL;
@property (nonatomic, copy) NSString *customModel;
@end

@implementation GMSettingsViewController

- (instancetype)initWithConversation:(GMConversation *)conversation {
    if ((self = [super initWithNibName:nil bundle:nil])) _conversation = conversation;
    return self;
}

- (void)loadView {
    self.view = [[UIView alloc] init];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.title = @"设置";
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone
                                        target:self action:@selector(save)];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.presets = [GMProviderPreset all];

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *savedIdent = [d stringForKey:@"gm.provider"] ?: @"deepseek";
    self.presetIndex = 0;
    for (NSInteger i = 0; i < self.presets.count; i++)
        if ([self.presets[i].identifier isEqualToString:savedIdent]) self.presetIndex = i;

    GMProviderPreset *p = self.presets[self.presetIndex];
    NSString *savedModel = [d stringForKey:@"gm.model"] ?: p.defaultModel;
    self.modelIndex = [p.models indexOfObject:savedModel];
    if (self.modelIndex == NSNotFound) self.modelIndex = 0;
    self.customURL = [d stringForKey:@"gm.baseURL"] ?: @"";
    self.customModel = savedModel;

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
}

- (GMProviderPreset *)current { return self.presets[self.presetIndex]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return s == 0 ? @"供应商" : (s == 1 ? @"模型" : @"密钥");
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) return @"选好供应商后，模型列表会自动更新。自定义可在下方填完整 URL。";
    if (s == 2) return [NSString stringWithFormat:@"Key 保存在系统 Keychain。申请地址：%@", self.current.keyHint];
    return nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return self.presets.count + (self.presetIndex == self.presets.count - 1 ? 1 : 0);
    if (s == 1) return MAX(1, MIN(self.current.models.count, 8)) + (self.presetIndex == self.presets.count - 1 ? 1 : 0);
    return 2; // key + 测试
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSString *ident = @"c";
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:ident];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:ident];

    if (ip.section == 0) {
        bool isCustom = (self.presetIndex == self.presets.count - 1);
        if (isCustom && ip.row == self.presets.count) {
            c.textLabel.text = @"自定义网关地址";
            self.urlField = self.urlField ?: [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 240, 30)];
            self.urlField.placeholder = @"https://host/v1/chat/completions";
            self.urlField.text = self.customURL;
            self.urlField.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
            self.urlField.autocapitalizationType = UITextAutocapitalizationTypeNone;
            self.urlField.autocorrectionType = UITextAutocorrectionTypeNo;
            c.accessoryView = self.urlField;
        } else {
            GMProviderPreset *p = self.presets[ip.row];
            c.textLabel.text = p.title;
            c.detailTextLabel.text = p.baseURL.length > 40 ?
                [p.baseURL substringToIndex:40] : p.baseURL;
            c.accessoryType = (ip.row == self.presetIndex) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        }
    } else if (ip.section == 1) {
        bool isCustom = (self.presetIndex == self.presets.count - 1);
        if (isCustom && ip.row == self.current.models.count) {
            c.textLabel.text = @"自定义模型名";
            self.modelField = self.modelField ?: [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 240, 30)];
            self.modelField.placeholder = @"model-slug";
            self.modelField.text = self.customModel;
            self.modelField.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
            self.modelField.autocapitalizationType = UITextAutocapitalizationTypeNone;
            c.accessoryView = self.modelField;
        } else {
            c.textLabel.text = self.current.models[ip.row];
            c.accessoryType = (ip.row == self.modelIndex) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        }
    } else {
        if (ip.row == 0) {
            c.textLabel.text = @"API Key";
            self.keyField = self.keyField ?: [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 240, 30)];
            self.keyField.placeholder = @"sk-…";
            self.keyField.secureTextEntry = YES;
            self.keyField.text = kcGet();
            self.keyField.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
            self.keyField.autocapitalizationType = UITextAutocapitalizationTypeNone;
            self.keyField.autocorrectionType = UITextAutocorrectionTypeNo;
            c.accessoryView = self.keyField;
        } else {
            c.textLabel.text = @"测试连接";
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    }
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0 && ip.row < self.presets.count) {
        self.presetIndex = ip.row;
        self.modelIndex = 0;
        [tv reloadData];
    } else if (ip.section == 1 && ip.row < self.current.models.count) {
        self.modelIndex = ip.row;
        [tv reloadData];
    } else if (ip.section == 2 && ip.row == 1) {
        [self testConnection];
    }
}

- (void)testConnection {
    NSString *url = [self resolvedURL];
    NSString *key = self.keyField.text ?: @"";
    NSString *model = [self resolvedModel];
    if (!url.length || !key.length) {
        [self alert:@"请先填写网关地址和 API Key"];
        return;
    }
    NSMutableDictionary *body = [NSMutableDictionary dictionary];
    body[@"model"] = model;
    body[@"messages"] = @[@{@"role": @"user", @"content": @"ping"}];
    body[@"max_tokens"] = @8;
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    r.HTTPMethod = @"POST";
    r.timeoutInterval = 25;
    [r setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    r.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [[[NSURLSession sharedSession] dataTaskWithRequest:r completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (e) { [self alert:[NSString stringWithFormat:@"网络错误：%@", e.localizedDescription]]; return; }
            NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
            NSString *text = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"";
            if (code >= 200 && code < 300) {
                [self alert:[NSString stringWithFormat:@"✅ 连接成功（%ld）\n模型：%@", (long)code, model]];
            } else {
                [self alert:[NSString stringWithFormat:@"❌ HTTP %ld\n%@", (long)code,
                             text.length > 200 ? [text substringToIndex:200] : text]];
            }
        });
    }] resume];
}

- (NSString *)resolvedURL {
    GMProviderPreset *p = self.current;
    if (self.presetIndex == self.presets.count - 1) return self.urlField.text ?: @"";
    return p.baseURL;
}
- (NSString *)resolvedModel {
    GMProviderPreset *p = self.current;
    if (self.presetIndex == self.presets.count - 1) return self.modelField.text ?: self.customModel;
    if (self.modelIndex >= 0 && self.modelIndex < p.models.count) return p.models[self.modelIndex];
    return p.defaultModel;
}

- (void)save {
    NSString *url = [self resolvedURL];
    NSString *model = [self resolvedModel];
    NSString *key = self.keyField.text ?: @"";
    if (![url hasPrefix:@"http"]) {
        [self alert:@"网关地址必须以 http:// 或 https:// 开头"];
        return;
    }
    if ([url hasSuffix:@"/"] || ![url containsString:@"/chat/completions"]) {
        [self alert:@"网关地址需完整到 /chat/completions\ne.g. https://api.deepseek.com/v1/chat/completions"];
        return;
    }
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:url forKey:@"gm.baseURL"];
    [d setObject:model forKey:@"gm.model"];
    [d setObject:key forKey:@"gm.apiKey"];
    [d setObject:self.current.identifier forKey:@"gm.provider"];
    [d setObject:@[@"low", @"medium", @"high"][1] forKey:@"gm.effort"];
    [d synchronize];
    kcSet(key);

    self.conversation.model = model;
    [self.conversation pushConfigToEngine];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)alert:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"GM Agent"
                                                              message:msg
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
