// GM Agent · JSON 最小实现（无第三方依赖）
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 解析 JSON 文本 -> NSDictionary/NSArray/NSNumber/NSString/NSNull
FOUNDATION_EXPORT id _Nullable GMJSONParse(NSString *text);

/// 序列化对象 -> JSON 文本（紧凑）
FOUNDATION_EXPORT NSString *GMJSONString(id obj);

NS_ASSUME_NONNULL_END
