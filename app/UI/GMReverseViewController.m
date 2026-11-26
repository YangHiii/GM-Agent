#import "GMReverseViewController.h"
#import "GMFilesViewController.h"

@implementation GMReverseViewController {
    NSString *_path;
    NSMutableArray<NSDictionary *> *_rows;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"逆向工具";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _rows = [NSMutableArray array];

    UITableView *tv = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    tv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    tv.dataSource = self;
    tv.delegate = self;
    tv.tag = 9001;
    [self.view addSubview:tv];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"选择文件" style:UIBarButtonItemStylePlain
                                        target:self action:@selector(pickFile)];
}

- (void)pickFile {
    GMFilesViewController *f = [[GMFilesViewController alloc] initAsPicker:^(NSString *p) {
        self->_path = p;
        [self analyze];
    }];
    f.startPath = @"/var/mobile";
    [self.navigationController pushViewController:f animated:YES];
}

- (UITableView *)tv { return (UITableView *)[self.view viewWithTag:9001]; }

- (void)analyze {
    [_rows removeAllObjects];
    if (!_path.length) { [self.tv reloadData]; return; }

    NSFileManager *fm = NSFileManager.defaultManager;
    NSDictionary *attr = [fm attributesOfItemAtPath:_path error:nil];
    [_rows addObject:@{@"t": @"路径", @"s": _path}];
    [_rows addObject:@{@"t": @"大小", @"s": [NSString stringWithFormat:@"%@ 字节",
                        @([attr[NSFileSize] longLongValue])]}];

    NSData *head = [NSData dataWithContentsOfFile:_path
                                         options:NSDataReadingMappedIfSafe
                                           error:nil];
    if (head.length < 32) {
        [_rows addObject:@{@"t": @"错误", @"s": @"文件太小，不是有效二进制"}];
        [self.tv reloadData];
        return;
    }
    const uint8_t *b = head.bytes;
    uint32_t magic = 0; memcpy(&magic, b, 4);

    NSString *arch = @"未知";
    uint32_t cpu = 0; memcpy(&cpu, b + 4, 4);
    if (magic == 0xfeedfacf || magic == 0xcffaedfe) {
        arch = (cpu == 0x0100000c) ? @"arm64" : (cpu == 0x0100000c + 1 ? @"arm64e" :
               [NSString stringWithFormat:@"cputype=0x%x", cpu]);
    } else if (magic == 0xcafebabe) {
        arch = @"fat (通用二进制)";
    } else {
        arch = [NSString stringWithFormat:@"非 Mach-O (magic=0x%08x)", magic];
    }
    [_rows addObject:@{@"t": @"架构", @"s": arch}];

    if (magic == 0xfeedfacf || magic == 0xcffaedfe) {
        uint32_t filetype = 0, ncmds = 0;
        memcpy(&filetype, b + 12, 4);
        memcpy(&ncmds, b + 16, 4);
        NSString *ft = filetype == 2 ? @"MH_EXECUTE" : filetype == 6 ? @"MH_DYLIB" :
                       filetype == 8 ? @"MH_BUNDLE" : [NSString stringWithFormat:@"%u", filetype];
        [_rows addObject:@{@"t": @"类型", @"s": ft}];
        [_rows addObject:@{@"t": @"Load Commands", @"s": [NSString stringWithFormat:@"%u 个", ncmds]}];

        // 遍历 load commands 找 LC_CODE_SIGNATURE / LC_ENCRYPTION_INFO
        uint32_t off = 32;
        BOOL hasSig = NO, encrypted = NO;
        uint32_t sigSize = 0;
        for (uint32_t i = 0; i < ncmds && off + 8 < head.length; i++) {
            uint32_t cmd, sz;
            memcpy(&cmd, b + off, 4);
            memcpy(&sz, b + off + 4, 4);
            if (cmd == 0x1d) { hasSig = YES; memcpy(&sigSize, b + off + 12, 4); }
            if (cmd == 0x21 || cmd == 0x2c) {
                uint32_t cryptid = 0;
                memcpy(&cryptid, b + off + 16, 4);
                if (cryptid != 0) encrypted = YES;
            }
            if (sz < 8) break;
            off += sz;
        }
        [_rows addObject:@{@"t": @"代码签名", @"s": hasSig ?
            [NSString stringWithFormat:@"有（%u 字节）", sigSize] : @"无（未签名）"}];
        [_rows addObject:@{@"t": @"加密", @"s": encrypted ? @"已加密（App Store 壳）" : @"未加密"}];
    }

    [self.tv reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 1; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return _rows.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"rv";
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cid];
    NSDictionary *r = _rows[ip.row];
    c.textLabel.text = r[@"t"];
    c.detailTextLabel.text = r[@"s"];
    c.detailTextLabel.numberOfLines = 2;
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    return c;
}

@end
