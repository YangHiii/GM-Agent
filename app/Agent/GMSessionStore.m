// GM Agent · 会话存储实现（NSUserDefaults 持久化元数据）
#import "GMSessionStore.h"

@implementation GMSessionMeta
- (NSDictionary *)dictionary {
    return @{
        @"id": self.threadID ?: @"",
        @"title": self.title ?: @"",
        @"at": @([self.updatedAt timeIntervalSince1970]),
    };
}
+ (instancetype)fromDictionary:(NSDictionary *)d {
    if (![d isKindOfClass:[NSDictionary class]]) return nil;
    GMSessionMeta *m = [GMSessionMeta new];
    m.threadID = d[@"id"];
    m.title = d[@"title"] ?: @"未命名";
    m.updatedAt = [NSDate dateWithTimeIntervalSince1970:[d[@"at"] doubleValue]];
    return m.threadID.length ? m : nil;
}
@end

@interface GMSessionStore ()
@property (nonatomic, strong) NSMutableArray<GMSessionMeta *> *items;
@end

@implementation GMSessionStore

+ (instancetype)shared {
    static GMSessionStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [GMSessionStore new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _items = [NSMutableArray array];
        NSArray *raw = [[NSUserDefaults standardUserDefaults] arrayForKey:@"gm.sessions"];
        for (NSDictionary *d in raw) {
            GMSessionMeta *m = [GMSessionMeta fromDictionary:d];
            if (m) [_items addObject:m];
        }
    }
    return self;
}

- (NSArray<GMSessionMeta *> *)sessions {
    return [_items sortedArrayUsingComparator:^NSComparisonResult(GMSessionMeta *a, GMSessionMeta *b) {
        return [b.updatedAt compare:a.updatedAt];
    }];
}

- (void)persist {
    NSMutableArray *arr = [NSMutableArray array];
    for (GMSessionMeta *m in _items) [arr addObject:[m dictionary]];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:arr forKey:@"gm.sessions"];
    [d synchronize];
}

- (GMSessionMeta *)createSessionWithTitle:(NSString *)title {
    GMSessionMeta *m = [GMSessionMeta new];
    long long ts = (long long)[NSDate.date timeIntervalSince1970];
    m.threadID = [NSString stringWithFormat:@"gm-%lld-%d", ts, arc4random_uniform(9000) + 1000];
    m.title = title.length ? title : @"新会话";
    m.updatedAt = [NSDate date];
    [_items insertObject:m atIndex:0];
    [self persist];
    return m;
}

- (void)updateSession:(NSString *)threadID title:(NSString *)title {
    for (GMSessionMeta *m in _items) {
        if ([m.threadID isEqualToString:threadID ?: @""]) {
            m.title = title;
            m.updatedAt = [NSDate date];
            [self persist];
            return;
        }
    }
}

- (void)touchSession:(NSString *)threadID {
    for (GMSessionMeta *m in _items) {
        if ([m.threadID isEqualToString:threadID ?: @""]) {
            m.updatedAt = [NSDate date];
            [self persist];
            return;
        }
    }
}

- (void)removeSession:(NSString *)threadID {
    NSInteger idx = -1;
    for (NSInteger i = 0; i < _items.count; i++) {
        if ([_items[i].threadID isEqualToString:threadID ?: @""]) { idx = i; break; }
    }
    if (idx >= 0) {
        [_items removeObjectAtIndex:idx];
        [self persist];
    }
}

- (NSString *)currentThreadID {
    return [[NSUserDefaults standardUserDefaults] stringForKey:@"gm.currentThread"];
}

- (void)setCurrentThreadID:(NSString *)tid {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (tid.length) [d setObject:tid forKey:@"gm.currentThread"];
    else [d removeObjectForKey:@"gm.currentThread"];
    [d synchronize];
}

@end
