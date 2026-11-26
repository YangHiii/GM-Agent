#import "GMWorkspaceStore.h"
#import "GMLog.h"

static NSString *const kKey = @"gm.workspaces";
static NSString *const kActive = @"gm.activeWorkspace";

@interface GMWorkspace ()
@end

@implementation GMWorkspace
- (NSDictionary *)dictionary {
    return @{@"ident": self.ident ?: @"",
             @"name": self.name ?: @"",
             @"path": self.path ?: @"",
             @"instruction": self.instruction ?: @"",
             @"at": @([self.createdAt timeIntervalSince1970])};
}
+ (instancetype)fromDictionary:(NSDictionary *)d {
    if (![d isKindOfClass:[NSDictionary class]]) return nil;
    GMWorkspace *w = [GMWorkspace new];
    w.ident = d[@"ident"];
    w.name = d[@"name"] ?: @"未命名";
    w.path = d[@"path"] ?: @"";
    w.instruction = d[@"instruction"] ?: @"";
    w.createdAt = [NSDate dateWithTimeIntervalSince1970:[d[@"at"] doubleValue]];
    return w.ident.length ? w : nil;
}
@end

@implementation GMWorkspaceStore

+ (instancetype)shared {
    static GMWorkspaceStore *s;
    static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [GMWorkspaceStore new]; });
    return s;
}

- (NSMutableArray<GMWorkspace *> *)_load {
    NSArray *raw = [[NSUserDefaults standardUserDefaults] arrayForKey:kKey];
    NSMutableArray<GMWorkspace *> *arr = [NSMutableArray array];
    for (NSDictionary *d in raw) {
        GMWorkspace *w = [GMWorkspace fromDictionary:d];
        if (w) [arr addObject:w];
    }
    if (arr.count == 0) {
        /* 首次：创建默认项目，路径为 /var/mobile/Documents */
        GMWorkspace *w = [GMWorkspace new];
        w.ident = [[NSUUID UUID] UUIDString];
        w.name = @"默认项目";
        w.path = @"/var/mobile/Documents";
        w.instruction = @"";
        w.createdAt = [NSDate date];
        [arr addObject:w];
        [self _save:arr];
        [[NSUserDefaults standardUserDefaults] setObject:w.ident forKey:kActive];
    }
    return arr;
}

- (void)_save:(NSArray<GMWorkspace *> *)list {
    NSMutableArray *raw = [NSMutableArray array];
    for (GMWorkspace *w in list) [raw addObject:[w dictionary]];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:raw forKey:kKey];
    [d synchronize];
}

- (NSArray<GMWorkspace *> *)workspaces {
    return [[self _load] sortedArrayUsingComparator:^NSComparisonResult(GMWorkspace *a, GMWorkspace *b) {
        return [a.createdAt compare:b.createdAt];
    }];
}

- (GMWorkspace *)active {
    NSString *ident = [[NSUserDefaults standardUserDefaults] stringForKey:kActive];
    for (GMWorkspace *w in [self _load]) if ([w.ident isEqualToString:ident ?: @""]) return w;
    return [self _load].firstObject;
}

- (GMWorkspace *)workspaceWithIdent:(NSString *)ident {
    for (GMWorkspace *w in [self _load]) if ([w.ident isEqualToString:ident ?: @""]) return w;
    return nil;
}

- (GMWorkspace *)addWorkspaceNamed:(NSString *)name path:(NSString *)path {
    NSMutableArray<GMWorkspace *> *list = [self _load];
    GMWorkspace *w = [GMWorkspace new];
    w.ident = [[NSUUID UUID] UUIDString];
    w.name = name.length ? name : @"新项目";
    w.path = path.length ? path : @"/var/mobile/Documents";
    w.instruction = @"";
    w.createdAt = [NSDate date];
    [list addObject:w];
    [self _save:list];
    GMLog(@"新增项目 %@ (%@)", w.name, w.path);
    return w;
}

- (void)updateWorkspace:(GMWorkspace *)ws {
    if (!ws.ident.length) return;
    NSMutableArray<GMWorkspace *> *list = [self _load];
    for (NSUInteger i = 0; i < list.count; i++) {
        if ([list[i].ident isEqualToString:ws.ident]) { list[i] = ws; break; }
    }
    [self _save:list];
}

- (void)removeWorkspace:(NSString *)ident {
    NSMutableArray<GMWorkspace *> *list = [self _load];
    if (list.count <= 1) return;   /* 至少保留一个 */
    [list filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(GMWorkspace *w, NSDictionary *b) {
        return ![w.ident isEqualToString:ident ?: @""];
    }]];
    [self _save:list];
    if ([self.active.ident isEqualToString:ident ?: @""]) {
        [[NSUserDefaults standardUserDefaults] setObject:list.firstObject.ident forKey:kActive];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (void)activateWorkspace:(NSString *)ident {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:ident ?: @"" forKey:kActive];
    [d synchronize];
    GMLog(@"切换项目 → %@", [self workspaceWithIdent:ident].name);
}
@end
