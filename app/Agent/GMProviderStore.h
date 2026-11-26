// GM Agent · 多供应商存储（对齐 MT 的 Provider List + Detail）
#import <Foundation/Foundation.h>

@interface GMProviderRecord : NSObject
@property (nonatomic, copy) NSString *ident;        // UUID
@property (nonatomic, copy) NSString *name;         // 显示名 / host
@property (nonatomic, copy) NSString *baseURL;      // 完整 chat/completions
@property (nonatomic, copy) NSString *apiKey;
@property (nonatomic, copy) NSString *model;
@property (nonatomic, copy) NSString *modelsJSON;   // 已发现的模型列表（JSON 数组）
@property (nonatomic) BOOL active;
- (NSDictionary *)dictionary;
+ (instancetype)fromDictionary:(NSDictionary *)d;
@end

@interface GMProviderStore : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSArray<GMProviderRecord *> *providers;
@property (nonatomic, readonly, nullable) GMProviderRecord *active;

- (GMProviderRecord *)addProviderNamed:(NSString *)name;
- (void)updateProvider:(GMProviderRecord *)rec;
- (void)removeProvider:(NSString *)ident;
- (void)activateProvider:(NSString *)ident;
/// 把当前激活供应商写入 gm.* 键，供引擎读取
- (void)applyActiveToDefaults;
@end
