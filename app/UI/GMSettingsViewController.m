// GM Agent · 设置页：网关 / 模型 / 推理强度 / API Key（存 Keychain）
#import "GMSettingsViewController.h"
#import <Security/Security.h>

static NSString *const kKeychainService = @"app.gm.agent";
static NSString *const kKeychainAccount = @"provider.apikey";

static void gm_keychain_set(NSString *value) {
    NSDictionary *q = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                        (__bridge id)kSecAttrService: kKeychainService,
                        (__bridge id)kSecAttrAccount: kKeychainAccount};
    SecItemDelete((__bridge CFDictionaryRef)q);
    if (!value.length) return;
    NSMutableDictionary *add = [q mutableCopy];
    add[(__bridge id)kSecValueData] = [value dataUsingEncoding:NSUTF8StringEncoding];
    add[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
    SecItemAdd((__bridge CFDictionaryRef)add, NULL);
}

static NSString *gm_keychain_get(void) {
    NSDictionary *q = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                        (__bridge id)kSecAttrService: kKeychainService,
                        (__bridge id)kSecAttrAccount: kKeychainAccount,
                        (__bridge id)kSecReturnData: @YES,
                        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne};
    CFTypeRef out = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &out) == errSecSuccess && out) {
        NSData *d = (__bridge_transfer NSData *)out;
        return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    }
    return @"";
}

@interface GMSettingsViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) GMConversation *conversation;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UITextField *baseURLField;
@property (nonatomic, strong) UITextField *modelField;
@property (nonatomic, strong) UITextField *keyField;
@property (nonatomic, strong) UISegmentedControl *effortControl;
@end

@implementation GMSettingsViewController

- (instancetype)initWithConversation:(GMConversation *)conversation {
    if ((self = [super initWithNibName:nil bundle:nil])) _conversation = conversation;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"设置";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone
                                        target:self action:@selector(save)];

    _table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _table.dataSource = self;
    _table.delegate = self;
    [self.view addSubview:_table];

    _baseURLField = [self fieldWithPlaceholder:@"https://api.openai.com/v1/chat/completions"];
    _baseURLField.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"gm.baseURL"] ?: @"";
    _modelField = [self fieldWithPlaceholder:@"gpt-5.2"];
    _modelField.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"gm.model"] ?: @"gpt-5.2";
    _keyField = [self fieldWithPlaceholder:@"sk-…"];
    _keyField.secureTextEntry = YES;
    _keyField.text = gm_keychain_get();

    _effortControl = [[UISegmentedControl alloc] initWithItems:@[@"low", @"medium", @"high"]];
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:@"gm.effort"] ?: @"medium";
    _effortControl.selectedSegmentIndex = [@[@"low", @"medium", @"high"] indexOfObject:saved];
    if (_effortControl.selectedSegmentIndex == NSNotFound) _effortControl.selectedSegmentIndex = 1;
}

- (UITextField *)fieldWithPlaceholder:(NSString *)ph {
    UITextField *f = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 260, 34)];
    f.placeholder = ph;
    f.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    f.autocapitalizationType = UITextAutocapitalizationTypeNone;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    return f;
}

- (void)save {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:self.baseURLField.text ?: @"" forKey:@"gm.baseURL"];
    [d setObject:self.modelField.text ?: @"gpt-5.2" forKey:@"gm.model"];
    [d setObject:@[@"low", @"medium", @"high"][MAX(0, (NSInteger)self.effortControl.selectedSegmentIndex)]
          forKey:@"gm.effort"];
    [d synchronize];
    gm_keychain_set(self.keyField.text);

    self.conversation.model = d[@"gm.model"] ?: @"gpt-5.2";
    self.conversation.effort = d[@"gm.effort"] ?: @"medium";
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 3 : 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"提供方" : @"推理强度";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 0 ? @"API Key 保存在系统 Keychain，不写入应用数据。" : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                  reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (indexPath.section == 0) {
        UITextField *f = indexPath.row == 0 ? _baseURLField : (indexPath.row == 1 ? _modelField : _keyField);
        f.frame = CGRectInset(cell.contentView.bounds, 16, 6);
        f.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [cell.contentView addSubview:f];
    } else {
        _effortControl.frame = CGRectInset(cell.contentView.bounds, 16, 6);
        _effortControl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [cell.contentView addSubview:_effortControl];
    }
    return cell;
}

@end
