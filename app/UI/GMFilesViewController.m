// GM Agent · 文件浏览：列目录、看文件、复制路径
#import "GMFilesViewController.h"
#import "GMLog.h"

@interface GMFilesViewController ()
@property (nonatomic, copy) NSString *path;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *items;
@end

@implementation GMFilesViewController

- (instancetype)initWithPath:(NSString *)path {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _path = [path copy] ?: NSHomeDirectory();
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.path.lastPathComponent.length ? self.path.lastPathComponent : @"/";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"doc.on.doc"]
                                         style:UIBarButtonItemStylePlain
                                        target:self action:@selector(copyPath)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
    [self reload];
}

- (void)reload {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray *names = [fm contentsOfDirectoryAtPath:self.path error:nil];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *n in names) {
        if ([n isEqualToString:@"."] || [n isEqualToString:@".."]) continue;
        NSString *full = [self.path stringByAppendingPathComponent:n];
        NSDictionary *attr = [fm attributesOfItemAtPath:full error:nil];
        BOOL isDir = [attr[NSFileType] isEqualToString:NSFileTypeDirectory];
        [rows addObject:@{@"name": n, @"path": full, @"dir": @(isDir),
                          @"size": attr[NSFileSize] ?: @0}];
    }
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        if ([a[@"dir"] boolValue] != [b[@"dir"] boolValue])
            return [a[@"dir"] boolValue] ? NSOrderedAscending : NSOrderedDescending;
        return [a[@"name"] compare:b[@"name"]];
    }];
    self.items = rows;
    self.title = self.path.lastPathComponent.length ? self.path.lastPathComponent : @"/";
    [self.tableView reloadData];
}

- (void)copyPath {
    [UIPasteboard generalPasteboard].string = self.path;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"路径已复制"
                                                             message:self.path
                                                      preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return MAX(self.items.count, 1);
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"f";
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    if (self.items.count == 0) {
        c.textLabel.text = @"(空目录)";
        c.detailTextLabel.text = nil;
        c.imageView.image = nil;
        return c;
    }
    NSDictionary *r = self.items[ip.row];
    BOOL dir = [r[@"dir"] boolValue];
    c.textLabel.text = dir ? [r[@"name"] stringByAppendingString:@"/"] : r[@"name"];
    c.textLabel.textColor = dir ? UIColor.labelColor : UIColor.secondaryLabelColor;
    c.imageView.image = [UIImage systemImageNamed:dir ? @"folder.fill" : @"doc.text"];
    c.imageView.tintColor = dir ? UIColor.systemBlueColor : UIColor.systemGrayColor;
    long long size = [r[@"size"] longLongValue];
    c.detailTextLabel.text = dir ? nil : [NSByteCountFormatter stringFromByteCount:size
                                                                       countStyle:NSByteCountFormatterCountStyleFile];
    c.detailTextLabel.font = [UIFont systemFontOfSize:11];
    c.accessoryType = dir ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.row >= self.items.count) return;
    NSDictionary *r = self.items[ip.row];
    if ([r[@"dir"] boolValue]) {
        [self.navigationController pushViewController:
            [[GMFilesViewController alloc] initWithPath:r[@"path"]] animated:YES];
        return;
    }
    NSString *content = [NSString stringWithContentsOfFile:r[@"path"]
                                                 encoding:NSUTF8StringEncoding error:nil];
    if (!content.length) {
        content = @"(二进制文件或无法以文本读取)";
    }
    if (content.length > 200000) content = [content substringToIndex:200000];
    UIViewController *vc = [UIViewController new];
    vc.title = r[@"name"];
    vc.view.backgroundColor = UIColor.systemBackgroundColor;
    UITextView *tx = [[UITextView alloc] initWithFrame:vc.view.bounds];
    tx.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tx.editable = NO;
    tx.text = content;
    tx.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    [vc.view addSubview:tx];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
