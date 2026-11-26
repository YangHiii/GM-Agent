#import "GMProviderStore.h"
#import <Security/Security.h>
#import "GMLog.h"

static NSString *const kListKey = @"gm.providers";
static NSString *const kActiveKey = @"gm.activeProvider";

static void kcSet(NSString *account, NSString *v) {
    NSDictionary *q = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                        (__bridge id)kSecAttrService: @"app.gm.agent.provider",
                        (__bridge id)kSecAttrAccount: account};
    SecItemDelete((__bridge CFDictionaryRef)q);
    if (!v.length) return;
    NSMutableDictionary *a = [q mutableCopy];
    a[(__bridge id)kSecValueData] = [v dataUsingEncoding:NSUTF8StringEncoding];
    a[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
    SecItemAdd((__bridge CFDictionaryRef)a, NULL);
}
static NSString *kcGet(NSString *account) {
    NSDictionary *q = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                        (__bridge id)kSecAttrService: @"app.gm.agent.provider",
                        (__bridge id)kSecAttrAccount: account,
                        (__bridge id)kSecReturnData: @YES,
                        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne};
    CFTypeRef out = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &out) == errSecSuccess && out) {
        NSData *d = (__bridge_transfer NSData *)out;
        return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    }
    return @"";
}

@implementation GMProviderRecord
- (NSDictionary *)dictionary {
    return @{@"ident": self.ident ?: @"",
             @"name": self.name ?: @"",
             @"baseURL": self.baseURL ?: @"",
             @"model": self.model ?: @"",
             @"models": self.modelsJSON ?: @"[]",
             @"active": @(self.active)};
}
+ (instancetype)fromDictionary:(NSDictionary *)d {
    GMProviderRecord *r = [GMProviderRecord new];
    r.ident = d[@"ident"];
    r.name = d[@"name"];
    r.baseURL = d[@"baseURL"];
    r.model = d[@"model"];
    r.modelsJSON = d[@"models"] ?: @"[]";
    r.active = [d[@"active"] boolValue];
    r.apiKey = kcGet(r.ident ?: @"");
    return r.ident.length ? r : nil;
}
@end

@implementation GMProviderStore

+ (instancetype)shared {
    static GMProviderStore *s;
    static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [GMProviderStore new]; });
    return s;
}

- (NSMutableArray<GMProviderRecord *> *)_load {
    NSArray *raw = [[NSUserDefaults standardUserDefaults] arrayForKey:kListKey];
    NSMutableArray<GMProviderRecord *> *arr = [NSMutableArray array];
    for (NSDictionary *d in raw) {
        GMProviderRecord *r = [GMProviderRecord fromDictionary:d];
        if (r) [arr addObject:r];
    }
    return arr;
}

- (void)_save:(NSArray<GMProviderRecord *> *)list {
    NSMutableArray<NSDictionary *> *raw = [NSMutableArray array];
    for (GMProviderRecord *r in list) [raw addObject:[r dictionary]];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject:raw forKey:kListKey];
    [d synchronize];
}

- (NSArray<GMProviderRecord *> *)providers { return [self _load]; }

- (GMProviderRecord *)active {
    for (GMProviderRecord *r in [self _load]) if (r.active) return r;
    return nil;
}

- (GMProviderRecord *)addProviderNamed:(NSString *)name {
    NSMutableArray<GMProviderRecord *> *list = [self _load];
    GMProviderRecord *r = [GMProviderRecord new];
    r.ident = [[NSUUID UUID] UUIDString];
    r.name = name ?: @"新供应商";
    r.baseURL = @"";
    r.model = @"";
    r.modelsJSON = @"[]";
    r.active = (list.count == 0);
    [list addObject:r];
    [self _save:list];
    GMLog(@"新增供应商 %@", r.ident);
    return r;
}

- (void)updateProvider:(GMProviderRecord *)rec {
    if (!rec.ident.length) return;
    NSMutableArray<GMProviderRecord *> *list = [self _load];
    for (NSUInteger i = 0; i < list.count; i++) {
        if ([list[i].ident isEqualToString:rec.ident]) {
            list[i] = rec;
            break;
        }
    }
    [self _save:list];
    kcSet(rec.ident, rec.apiKey ?: @"");
    if (rec.active) [self applyActiveToDefaults];
}

- (void)removeProvider:(NSString *)ident {
    NSMutableArray<GMProviderRecord *> *list = [self _load];
    GMProviderRecord *removed = nil;
    for (GMProviderRecord *r in list) if ([r.ident isEqualToString:ident]) { removed = r; break; }
    [list filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(GMProviderRecord *r, NSDictionary *b) {
        return ![r.ident isEqualToString:ident];
    }]];
    kcSet(ident, @"");
    if (removed.active && list.count) {
        GMProviderRecord *first = list.firstObject;
        first.active = YES;
    }
    [self _save:list];
    [self applyActiveToDefaults];
}

- (void)activateProvider:(NSString *)ident {
    NSMutableArray<GMProviderRecord *> *list = [self _load];
    for (GMProviderRecord *r in list) r.active = [r.ident isEqualToString:ident];
    [self _save:list];
    [self applyActiveToDefaults];
}

- (void)applyActiveToDefaults {
    GMProviderRecord *r = self.active;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (!r) {
        [d removeObjectForKey:@"gm.baseURL"];
        [d removeObjectForKey:@"gm.apiKey"];
        [d removeObjectForKey:@"gm.model"];
        [d removeObjectForKey:@"gm.providerName"];
        [d synchronize];
        return;
    }
    if (r.baseURL.length) [d setObject:r.baseURL forKey:@"gm.baseURL"];
    if (r.apiKey.length) [d setObject:r.apiKey forKey:@"gm.apiKey"];
    if (r.model.length) [d setObject:r.model forKey:@"gm.model"];
    {
        NSURL *u = [NSURL URLWithString:r.baseURL ?: @""];
        if (u.host.length) [d setObject:u.host forKey:@"gm.providerName"];
    }
    [d synchronize];
    GMLog(@"已激活供应商 %@ (%@)", r.name, r.model);
}
@end
