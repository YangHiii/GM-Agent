// GM Agent · 事件模型实现
#import "GMMessage.h"

@implementation GMMessage
+ (instancetype)userText:(NSString *)text {
    GMMessage *m = [GMMessage new];
    m.role = GMRoleUser;
    m.text = text ?: @"";
    return m;
}
+ (instancetype)assistantText:(NSString *)text {
    GMMessage *m = [GMMessage new];
    m.role = GMRoleAssistant;
    m.text = text ?: @"";
    return m;
}
+ (instancetype)tool:(NSString *)name summary:(NSString *)summary {
    GMMessage *m = [GMMessage new];
    m.role = GMRoleTool;
    m.toolName = name;
    m.toolSummary = summary;
    m.text = summary ?: @"";
    return m;
}
- (NSString *)description {
    return [NSString stringWithFormat:@"<GMMessage %ld: %@>", (long)self.role,
            [self.text substringToIndex:MIN(self.text.length, 40)]];
}
@end
