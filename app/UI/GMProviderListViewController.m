#import "GMProviderListViewController.h"
#import "GMProviderStore.h"
#import "GMAIAccountViewController.h"
#import "GMLog.h"

@interface GMProviderListViewController ()
@property (nonatomic, strong) GMConversation *conversation;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) NSArray<GMProviderRecord *> *items;
@end

@implementation GMProviderListViewController

- (instancetype)initWithConversation:(GMConversation *)conversation {
    if ((self = [super initWithNibName:nil bundle:nil])) _conversation = conversation;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"供应商";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                      target:self action:@selector(addProvider)];
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.view addSubview:self.table];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)reload {
    self.items = [GMProviderStore shared].providers;
    [self.table reloadData];
}

- (void)addProvider {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"新建供应商"
                                                            message:@"给这个供应商起个名字"
                                                     preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"例如 DeepSeek";
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *name = a.textFields.firstObject.text;
        GMProviderRecord *r = [[GMProviderStore shared] addProviderNamed:name.length ? name : @"新供应商"];
        [self openDetail:r.ident];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)openDetail:(NSString *)ident {
    GMAIAccountViewController *vc = [[GMAIAccountViewController alloc]
                                     initWithConversation:self.conversation providerIdent:ident];
    [self.navigationController pushViewController:vc animated:YES];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return MAX(self.items.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"p";
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    if (self.items.count == 0) {
        c.textLabel.text = @"还没有供应商";
        c.detailTextLabel.text = @"点右上角 + 添加";
        c.textLabel.textColor = UIColor.secondaryLabelColor;
        c.accessoryType = UITableViewCellAccessoryNone;
        c.imageView.image = nil;
        return c;
    }
    GMProviderRecord *r = self.items[ip.row];
    c.textLabel.text = r.name.length ? r.name : r.ident;
    c.textLabel.textColor = UIColor.labelColor;
    NSString *sub = r.model.length ? [NSString stringWithFormat:@"%@ · %@", r.baseURL, r.model] : @"未配置";
    c.detailTextLabel.text = sub;
    c.detailTextLabel.font = [UIFont systemFontOfSize:11];
    c.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    c.imageView.image = [UIImage systemImageNamed:r.active ? @"checkmark.circle.fill" : @"globe"];
    c.imageView.tintColor = r.active ? UIColor.systemGreenColor : UIColor.systemGrayColor;
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.row >= self.items.count) return;
    GMProviderRecord *r = self.items[ip.row];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:r.name message:nil
                                                      preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"编辑配置" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self openDetail:r.ident];
    }]];
    if (!r.active) {
        [a addAction:[UIAlertAction actionWithTitle:@"设为当前" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [[GMProviderStore shared] activateProvider:r.ident];
            [self reload];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [[GMProviderStore shared] removeProvider:r.ident];
        [self reload];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = tv;
    a.popoverPresentationController.sourceRect = [tv rectForRowAtIndexPath:ip];
    [self presentViewController:a animated:YES completion:nil];
}

@end
