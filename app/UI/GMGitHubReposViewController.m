// GM Agent · GitHub 仓库 / 提交 / 文件 / Issue
#import "GMGitHubReposViewController.h"
#import <Security/Security.h>
#import "GMLog.h"

@interface NSString (GMSub)
- (NSString *)substringToIndexSafe:(NSUInteger)n;
@end

static NSString *GHPAT(void) {
    NSDictionary *q = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                        (__bridge id)kSecAttrService: @"app.gm.agent.github",
                        (__bridge id)kSecAttrAccount: @"pat",
                        (__bridge id)kSecReturnData: @YES,
                        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne};
    CFTypeRef out = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &out) == errSecSuccess && out) {
        NSData *d = (__bridge_transfer NSData *)out;
        return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    }
    return @"";
}

static void GHGet(NSString *path, void (^done)(id obj, NSInteger code, NSString *err)) {
    NSString *pat = GHPAT();
    if (!pat.length) { done(nil, 0, @"未登录 GitHub"); return; }
    NSString *url = [@"https://api.github.com" stringByAppendingString:path];
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    r.timeoutInterval = 25;
    [r setValue:[@"Bearer " stringByAppendingString:pat] forHTTPHeaderField:@"Authorization"];
    [r setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [r setValue:@"gm-agent" forHTTPHeaderField:@"User-Agent"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:r
                                    completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
            if (err) { done(nil, code, err.localizedDescription); return; }
            id obj = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if (code >= 400) {
                NSString *msg = [obj isKindOfClass:[NSDictionary class]] ? obj[@"message"] : nil;
                done(nil, code, msg ?: [NSString stringWithFormat:@"HTTP %ld", (long)code]);
                return;
            }
            done(obj, code, nil);
        });
    }] resume];
}

#pragma mark - 通用列表

typedef void (^GHRowTap)(NSDictionary *row);

@interface GHListViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSString *apiPath;
@property (nonatomic, copy) NSString *rowTitleKey;
@property (nonatomic, copy) NSString *rowSubKey;
@property (nonatomic, copy) NSString *emptyText;
@property (nonatomic, copy) GHRowTap onTap;
@property (nonatomic, strong) NSArray<NSDictionary *> *rows;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refresh;
@end

@implementation GHListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
    self.refresh = [UIRefreshControl new];
    [self.refresh addTarget:self action:@selector(load) forControlEvents:UIControlEventValueChanged];
    self.tableView.refreshControl = self.refresh;
    [self load];
}

- (void)load {
    [self.refresh beginRefreshing];
    __weak typeof(self) wself = self;
    GHGet(self.apiPath, ^(id obj, NSInteger code, NSString *err) {
        __strong typeof(wself) s = wself;
        if (!s) return;
        [s.refresh endRefreshing];
        if (err) {
            s.rows = @[];
            [s.tableView reloadData];
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"加载失败"
                                                                     message:err
                                                              preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [s presentViewController:a animated:YES completion:nil];
            return;
        }
        s.rows = [obj isKindOfClass:[NSArray class]] ? obj : @[];
        [s.tableView reloadData];
    });
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)sec {
    return MAX(self.rows.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"r";
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    if (self.rows.count == 0) {
        c.textLabel.text = self.emptyText ?: @"(空)";
        c.textLabel.textColor = UIColor.secondaryLabelColor;
        c.detailTextLabel.text = nil;
        c.accessoryType = UITableViewCellAccessoryNone;
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        return c;
    }
    NSDictionary *r = self.rows[ip.row];
    id t = self.rowTitleKey ? r[self.rowTitleKey] : nil;
    if ([t isKindOfClass:[NSDictionary class]]) t = ((NSDictionary *)t)[@"name"];
    c.textLabel.text = [t isKindOfClass:[NSString class]] ? t : [[r description] substringToIndexSafe:40];
    c.textLabel.textColor = UIColor.labelColor;
    if (self.rowSubKey) {
        id sub = r[self.rowSubKey];
        if ([sub isKindOfClass:[NSDictionary class]]) {
            sub = ((NSDictionary *)sub)[@"login"] ?: ((NSDictionary *)sub)[@"message"];
        }
        c.detailTextLabel.text = [sub isKindOfClass:[NSString class]] ? sub : nil;
    }
    c.detailTextLabel.font = [UIFont systemFontOfSize:11];
    c.accessoryType = self.onTap ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.row >= self.rows.count || !self.onTap) return;
    self.onTap(self.rows[ip.row]);
}

@end

@implementation NSString (GMSub)
- (NSString *)substringToIndexSafe:(NSUInteger)n {
    return self.length > n ? [self substringToIndex:n] : self;
}
@end

#pragma mark - 仓库列表

@implementation GMGitHubReposViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"GitHub 仓库";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                      target:self action:@selector(openList)];
    [self openList];
}

- (void)openList {
    if (!GHPAT().length) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"未登录"
                                                                 message:@"请先在「GitHub 账号管理」中填写并验证访问令牌。"
                                                          preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    GHListViewController *vc = [GHListViewController new];
    vc.title = @"仓库";
    vc.apiPath = @"/user/repos?per_page=50&sort=updated";
    vc.rowTitleKey = @"full_name";
    vc.rowSubKey = @"description";
    vc.emptyText = @"没有仓库";
    vc.onTap = ^(NSDictionary *row) {
        NSString *full = row[@"full_name"];
        if (!full.length) return;
        [self openRepo:full];
    };
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)openRepo:(NSString *)full {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:full
                                                             message:@"选择要查看的内容"
                                                      preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"最近提交" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self commitsFor:full];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"文件列表" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self contentsFor:full path:@""];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Issues" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        GHListViewController *vc = [GHListViewController new];
        vc.title = @"Issues";
        vc.apiPath = [NSString stringWithFormat:@"/repos/%@/issues?per_page=30&state=all", full];
        vc.rowTitleKey = @"title";
        vc.rowSubKey = @"user";
        vc.emptyText = @"没有 Issue";
        [self.navigationController pushViewController:vc animated:YES];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = self.view;
    a.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, 200, 1, 1);
    [self presentViewController:a animated:YES completion:nil];
}

- (void)commitsFor:(NSString *)full {
    GHListViewController *vc = [GHListViewController new];
    vc.title = @"提交";
    vc.apiPath = [NSString stringWithFormat:@"/repos/%@/commits?per_page=30", full];
    vc.rowTitleKey = @"commit";
    vc.rowSubKey = @"sha";
    vc.emptyText = @"没有提交";
    vc.onTap = ^(NSDictionary *row) {
        NSDictionary *c = row[@"commit"];
        NSMutableString *msg = [NSMutableString string];
        [msg appendFormat:@"%@\n\n作者：%@\n", c[@"message"] ?: @"",
                          c[@"author"][@"name"] ?: row[@"author"][@"login"] ?: @"?"];
        NSString *sha = row[@"sha"];
        if (sha.length) [msg appendFormat:@"\nSHA: %@", sha];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"提交详情"
                                                                 message:msg
                                                          preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    };
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)contentsFor:(NSString *)full path:(NSString *)path {
    GHListViewController *vc = [GHListViewController new];
    vc.title = path.length ? path : @"文件";
    vc.apiPath = [NSString stringWithFormat:@"/repos/%@/contents/%@", full, path];
    vc.rowTitleKey = @"name";
    vc.rowSubKey = @"type";
    vc.emptyText = @"没有文件";
    vc.onTap = ^(NSDictionary *row) {
        NSString *type = row[@"type"];
        NSString *name = row[@"name"];
        if ([type isEqualToString:@"dir"]) {
            [self contentsFor:full path:name];
            return;
        }
        NSString *download = row[@"download_url"];
        if (download.length) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:download]
                                               options:@{} completionHandler:nil];
        }
    };
    [self.navigationController pushViewController:vc animated:YES];
}

@end
