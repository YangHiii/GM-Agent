// GM Agent · 会话存储（列表元数据 + 当前会话）
#import <Foundation/Foundation.h>

@interface GMSessionMeta : NSObject
@property (nonatomic, copy) NSString *threadID;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSDate *updatedAt;
@end

@interface GMSessionStore : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSArray<GMSessionMeta *> *sessions;
- (GMSessionMeta *)createSessionWithTitle:(NSString *)title;
- (void)updateSession:(NSString *)threadID title:(NSString *)title;
- (void)touchSession:(NSString *)threadID;
- (void)removeSession:(NSString *)threadID;
- (NSString *)currentThreadID;
- (void)setCurrentThreadID:(NSString *)tid;
@end
