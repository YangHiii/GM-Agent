#import "GMPlanViewController.h"
#import "GMRingView.h"

@implementation GMPlanStep
@end

#pragma mark - 进度

@interface GMPlanProgressViewController ()
@property (nonatomic, copy) NSString *task;
@property (nonatomic, strong) NSArray<GMPlanStep *> *steps;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) GMRingView *ring;
@property (nonatomic, strong) UILabel *taskLabel;
@end

@implementation GMPlanProgressViewController

- (instancetype)initWithTask:(NSString *)task steps:(NSArray<GMPlanStep *> *)steps {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _task = [task copy];
        _steps = steps ?: @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"计划进度";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.ring = [[GMRingView alloc] initWithFrame:CGRectMake(0, 0, 64, 64)];
    self.ring.lineWidth = 5;
    self.ring.translatesAutoresizingMaskIntoConstraints = NO;

    self.taskLabel = [UILabel new];
    self.taskLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.taskLabel.font = [UIFont systemFontOfSize:13];
    self.taskLabel.textColor = UIColor.secondaryLabelColor;
    self.taskLabel.numberOfLines = 0;
    self.taskLabel.text = self.task;

    self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.rowHeight = 52;

    [self.view addSubview:self.ring];
    [self.view addSubview:self.taskLabel];
    [self.view addSubview:self.table];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.ring.topAnchor constraintEqualToAnchor:safe.topAnchor constant:16],
        [self.ring.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],
        [self.ring.widthAnchor constraintEqualToConstant:64],
        [self.ring.heightAnchor constraintEqualToConstant:64],

        [self.taskLabel.leadingAnchor constraintEqualToAnchor:self.ring.trailingAnchor constant:14],
        [self.taskLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],
        [self.taskLabel.centerYAnchor constraintEqualToAnchor:self.ring.centerYAnchor],

        [self.table.topAnchor constraintEqualToAnchor:self.ring.bottomAnchor constant:12],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
    [self refreshRing];
}

- (void)updateSteps:(NSArray<GMPlanStep *> *)steps {
    self.steps = steps ?: @[];
    [self.table reloadData];
    [self refreshRing];
}

- (void)refreshRing {
    if (!self.steps.count) { self.ring.progress = 0; return; }
    NSInteger done = 0;
    for (GMPlanStep *s in self.steps) if (s.state == 2) done++;
    self.ring.centerText = [NSString stringWithFormat:@"%ld/%lu", (long)done, (unsigned long)self.steps.count];
    [self.ring setProgress:(CGFloat)done / (CGFloat)self.steps.count animated:YES];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return MAX(self.steps.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"ps";
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
    if (!self.steps.count) {
        c.textLabel.text = @"暂无步骤";
        c.textLabel.textColor = UIColor.secondaryLabelColor;
        c.imageView.image = nil;
        return c;
    }
    GMPlanStep *s = self.steps[ip.row];
    c.textLabel.text = s.title;
    c.textLabel.textColor = s.state == 2 ? UIColor.secondaryLabelColor : UIColor.labelColor;
    NSString *sym;
    UIColor *tint;
    switch (s.state) {
        case 1: sym = @"circle.dotted"; tint = UIColor.systemBlueColor; break;
        case 2: sym = @"checkmark.circle.fill"; tint = UIColor.systemGreenColor; break;
        case 3: sym = @"xmark.circle.fill"; tint = UIColor.systemRedColor; break;
        default: sym = @"circle"; tint = UIColor.tertiaryLabelColor; break;
    }
    c.imageView.image = [UIImage systemImageNamed:sym];
    c.imageView.tintColor = tint;
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    return c;
}

@end

#pragma mark - 复核

@interface GMPlanReviewViewController ()
@property (nonatomic, copy) NSString *task;
@property (nonatomic, strong) NSArray<GMPlanStep *> *steps;
@property (nonatomic, strong) UITableView *table;
@end

@implementation GMPlanReviewViewController

- (instancetype)initWithTask:(NSString *)task steps:(NSArray<GMPlanStep *> *)steps {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _task = [task copy];
        _steps = steps ?: @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"计划复核";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.rowHeight = 52;
    [self.view addSubview:self.table];

    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 60)];
    UIButton *accept = [UIButton buttonWithType:UIButtonTypeSystem];
    accept.frame = CGRectMake(16, 8, footer.bounds.size.width - 32, 44);
    accept.backgroundColor = UIColor.systemBlueColor;
    accept.layer.cornerRadius = 10;
    [accept setTitle:@"接受计划并执行" forState:UIControlStateNormal];
    [accept setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    accept.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [accept addTarget:self action:@selector(acceptPlan) forControlEvents:UIControlEventTouchUpInside];
    [footer addSubview:accept];
    self.table.tableFooterView = footer;
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"拒绝" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(rejectPlan)];
}

- (void)acceptPlan {
    if (self.onAccept) self.onAccept();
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)rejectPlan {
    if (self.onReject) self.onReject();
    [self.navigationController popViewControllerAnimated:YES];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return s == 0 ? @"任务" : @"计划步骤";
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return s == 0 ? 1 : MAX(self.steps.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"rv";
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    if (ip.section == 0) {
        c.textLabel.text = self.task;
        c.textLabel.numberOfLines = 0;
        c.textLabel.font = [UIFont systemFontOfSize:14];
    } else {
        if (!self.steps.count) {
            c.textLabel.text = @"暂无步骤";
            c.textLabel.textColor = UIColor.secondaryLabelColor;
        } else {
            c.textLabel.text = [NSString stringWithFormat:@"%ld. %@", (long)(ip.row + 1), self.steps[ip.row].title];
            c.textLabel.textColor = UIColor.labelColor;
        }
    }
    return c;
}

@end

#pragma mark - 决策

@interface GMPlanDecisionViewController ()
@property (nonatomic, copy) NSString *task;
@property (nonatomic, copy) NSString *output;
@end

@implementation GMPlanDecisionViewController

- (instancetype)initWithTask:(NSString *)task output:(NSString *)output {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _task = [task copy];
        _output = [output copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"子代理结果";
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UITextView *tv = [[UITextView alloc] initWithFrame:self.view.bounds];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.editable = NO;
    tv.font = [UIFont systemFontOfSize:13];
    tv.text = [NSString stringWithFormat:@"任务：%@\n\n%@", self.task ?: @"", self.output ?: @"(无输出)"];
    [self.view addSubview:tv];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"复制"
                                         style:UIBarButtonItemStylePlain
                                        target:self action:@selector(copyOutput)];
}

- (void)copyOutput {
    [UIPasteboard generalPasteboard].string = self.output ?: @"";
}

@end
