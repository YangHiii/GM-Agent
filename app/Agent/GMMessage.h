// GM Agent · 事件模型
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, GMRole) { GMRoleUser = 0, GMRoleAssistant, GMRoleSystem, GMRoleTool };

@interface GMMessage : NSObject
@property (nonatomic) GMRole role;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *reasoning;
@property (nonatomic, copy) NSString *toolName;
@property (nonatomic, copy) NSString *toolSummary;
@property (nonatomic, copy) NSString *itemID;
@property (nonatomic) BOOL streaming;
+ (instancetype)userText:(NSString *)text;
+ (instancetype)assistantText:(NSString *)text;
+ (instancetype)tool:(NSString *)name summary:(NSString *)summary;
@end
