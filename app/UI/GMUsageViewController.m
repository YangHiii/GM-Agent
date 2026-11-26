// GM Agent · 用量统计：今日/累计 token，按模型价格折算人民币（汇率来自 frankfurter.dev）
#import "GMUsageViewController.h"
#import "GMLog.h"

static NSString *const kRateURL = @"https://api.frankfurter.dev/v2/rate/usd/cny";

@implementation GMUsageViewController {
    UITableView *_table;
    NSArray<NSArray<NSString *>> *_rows;
    double _rate;            // USD -> CNY
    double _todayCost;
    double _totalCost;
    long long _todayIn, _todayOut, _totalIn, _totalOut;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"用量统计";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                      target:self action:@selector(loadRate)];

    _table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _table.dataSource = self;
    _table.delegate = self;
    [self.view addSubview:_table];

    [self loadData];
    [self loadRate];
}

#pragma mark - 数据

/// 每百万 token 的美元价格（输入, 输出）
- (NSArray<NSNumber *> *)priceForModel:(NSString *)m {
    NSDictionary *t = @{
        @"gpt-5.2": @[@1.75, @14.0], @"gpt-5.1": @[@1.25, @10.0],
        @"gpt-5": @[@1.25, @10.0], @"gpt-4.1": @[@2.0, @8.0], @"gpt-4o": @[@2.5, @10.0],
        @"deepseek-chat": @[@0.27, @1.10], @"deepseek-reasoner": @[@0.55, @2.19],
        @"deepseek-v4-pro": @[@0.60, @2.20], @"deepseek-flash": @[@0.14, @0.28],
        @"gemini-2.5-pro": @[@1.25, @10.0], @"gemini-2.5-flash": @[@0.30, @2.50],
        @"kimi-k2-0905-preview": @[@0.60, @2.50], @"moonshot-v1-128k": @[@1.68, @1.68],
        @"glm-4.6": @[@0.60, @2.20], @"glm-4-plus": @[@0.70, @0.70],
        @"qwen3-max": @[@1.20, @6.00], @"qwen-plus": @[@0.40, @1.20],
    };
    for (NSString *k in t) if ([m hasPrefix:k]) return t[k];
    return @[@1.0, @3.0];
}

- (void)loadData {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    _totalIn = [[d objectForKey:@"gm.tokens.in"] longLongValue];
    _totalOut = [[d objectForKey:@"gm.tokens.out"] longLongValue];
    _todayIn = [[d objectForKey:@"gm.tokens.today.in"] longLongValue];
    _todayOut = [[d objectForKey:@"gm.tokens.today.out"] longLongValue];
    /* 今日计数：若日期不同则归零 */
    NSString *today = [[NSDateFormatter new] stringFromDate:[NSDate date]];
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"yyyy-MM-dd";
    today = [f stringFromDate:[NSDate date]];
    NSString *savedDay = [d stringForKey:@"gm.tokens.day"];
    if (![today isEqualToString:savedDay ?: @""]) {
        [d setObject:today forKey:@"gm.tokens.day"];
        [d setObject:@0 forKey:@"gm.tokens.today.in"];
        [d setObject:@0 forKey:@"gm.tokens.today.out"];
        [d synchronize];
        _todayIn = _todayOut = 0;
    }
    [self recompute];
    [_table reloadData];
}

- (void)recompute {
    NSString *model = [[NSUserDefaults standardUserDefaults] stringForKey:@"gm.model"] ?: @"";
    NSArray<NSNumber *> *p = [self priceForModel:model];
    double pin = p[0].doubleValue, pout = p[1].doubleValue;
    double r = _rate > 0 ? _rate : 7.2;
    _todayCost = (_todayIn / 1e6 * pin + _todayOut / 1e6 * pout) * r;
    _totalCost = (_totalIn / 1e6 * pin + _totalOut / 1e6 * pout) * r;
}

- (void)loadRate {
    NSURLRequest *req = [NSURLRequest requestWithURL:[NSURL URLWithString:kRateURL]
                                        cachePolicy:NSURLRequestReloadIgnoringCacheData
                                    timeoutInterval:20];
    __weak typeof(self) wself = self;
    [[[NSURLSession sharedSession] dataTaskWithRequest:req
                                    completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(wself) s = wself;
            if (!s || err || !data) return;
            id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            double r = 0;
            if ([obj isKindOfClass:[NSDictionary class]]) {
                r = [obj[@"rate"] doubleValue];
                if (r <= 0 && [obj[@"rates"] isKindOfClass:[NSDictionary class]])
                    r = [obj[@"rates"][@"CNY"] doubleValue];
            }
            if (r > 0) {
                s->_rate = r;
                GMLog(@"汇率 USD→CNY = %.4f", r);
                [s recompute];
                [s->_table reloadData];
            }
        });
    }] resume];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return @[@"今日", @"累计", @"当前模型"][s];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 1) {
        return [NSString stringWithFormat:@"汇率 1 USD ≈ %.4f CNY（来自 frankfurter.dev）\n价格按模型内置表估算，仅供参考。",
                _rate > 0 ? _rate : 7.2];
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return s == 2 ? 2 : 3;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"u";
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cid];
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    c.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];

    if (ip.section == 0) {
        if (ip.row == 0) { c.textLabel.text = @"输入 tokens"; c.detailTextLabel.text = [NSString stringWithFormat:@"%lld", _todayIn]; }
        else if (ip.row == 1) { c.textLabel.text = @"输出 tokens"; c.detailTextLabel.text = [NSString stringWithFormat:@"%lld", _todayOut]; }
        else { c.textLabel.text = @"今日费用"; c.detailTextLabel.text = [NSString stringWithFormat:@"¥%.4f", _todayCost]; c.detailTextLabel.textColor = UIColor.systemGreenColor; }
    } else if (ip.section == 1) {
        if (ip.row == 0) { c.textLabel.text = @"输入 tokens"; c.detailTextLabel.text = [NSString stringWithFormat:@"%lld", _totalIn]; }
        else if (ip.row == 1) { c.textLabel.text = @"输出 tokens"; c.detailTextLabel.text = [NSString stringWithFormat:@"%lld", _totalOut]; }
        else { c.textLabel.text = @"累计费用"; c.detailTextLabel.text = [NSString stringWithFormat:@"¥%.4f", _totalCost]; c.detailTextLabel.textColor = UIColor.systemBlueColor; }
    } else {
        if (ip.row == 0) {
            c.textLabel.text = @"模型";
            c.detailTextLabel.text = [[NSUserDefaults standardUserDefaults] stringForKey:@"gm.model"] ?: @"未配置";
        } else {
            c.textLabel.text = @"重置累计";
            c.textLabel.textColor = UIColor.systemRedColor;
            c.detailTextLabel.text = nil;
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
    }
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section != 2 || ip.row != 1) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"重置用量"
                                                            message:@"将清零今日与累计统计，不可恢复。"
                                                     preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"重置" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        for (NSString *k in @[@"gm.tokens.in", @"gm.tokens.out", @"gm.tokens.today.in", @"gm.tokens.today.out"])
            [d setObject:@0 forKey:k];
        [d synchronize];
        [self loadData];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
