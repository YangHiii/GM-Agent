// GM Agent · 模型与供应商预设
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GMProviderPreset : NSObject
@property (nonatomic, copy) NSString *identifier;   // deepseek / openai / ...
@property (nonatomic, copy) NSString *title;        // DeepSeek
@property (nonatomic, copy) NSString *baseURL;      // 完整 chat/completions 地址
@property (nonatomic, copy) NSString *defaultModel; // 默认模型 slug
@property (nonatomic, strong) NSArray<NSString *> *models;
@property (nonatomic, copy) NSString *keyHint;      // 申请地址
+ (NSArray<GMProviderPreset *> *)all;
+ (nullable GMProviderPreset *)presetForIdentifier:(nullable NSString *)ident;
@end

NS_ASSUME_NONNULL_END
