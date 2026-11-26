// GM Agent · 会话列表：切换 / 删除 / 新建
#import "GMSessionListViewController.h"
#import "GMSessionStore.h"
#import "GMLog.h"

@interface GMSessionListViewController ()
@property (nonatomic, strong) GMConversation *conversation;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<GMSessionMeta *> *items;
@end

@implementation GMSessionListViewController

- (instancetype)initWithConversation:(GMConversation *)conversation {
    if ((self = [super initWithNibName:nil bundle:nil])) _conversation = conversation;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"会话";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                      target:self action:@selector(newSession)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
    [self reload];
}

- (void)reload {
    self.items = [GMSessionStore shared].sessions;
    [self.tableView reloadData];
}

- (void)newSession {
    GMSessionMeta *m = [[GMSessionStore shared] createSessionWithTitle:@"新会话"];
    [[GMSessionStore shared] setCurrentThreadID:m.threadID];
    [self.conversation loadThread:m.threadID];
    [self.navigationController popViewControllerAnimated:YES];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return MAX(self.items.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"s";
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    if (self.items.count == 0) {
        c.textLabel.text = @"还没有会话";
        c.detailTextLabel.text = @"点右上角 + 新建";
        c.textLabel.textColor = UIColor.secondaryLabelColor;
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        return c;
    }
    GMSessionMeta *m = self.items[ip.row];
    c.textLabel.text = m.title;
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"MM-dd HH:mm";
    c.detailTextLabel.text = [f stringFromDate:m.updatedAt];
    BOOL cur = [m.threadID isEqualToString:[[GMSessionStore shared] currentThreadID] ?: @""];
    c.accessoryType = cur ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.row >= self.items.count) return;
    GMSessionMeta *m = self.items[ip.row];
    [self.conversation loadThread:m.threadID];
    [self.navigationController popViewControllerAnimated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.row >= self.items.count) return nil;
    GMSessionMeta *m = self.items[ip.row];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                      title:@"删除"
                                                                    handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        [[GMSessionStore shared] removeSession:m.threadID];
        if ([m.threadID isEqualToString:[[GMSessionStore shared] currentThreadID] ?: @""]) {
            [self.conversation newThread];
        }
        [self reload];
        done(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

@end
