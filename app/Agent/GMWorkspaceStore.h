// GM Agent · 工作区/项目（对齐 MT 的 CAWorkspaceViewController）
#import <Foundation/Foundation.h>

@interface GMWorkspace : NSObject
@property (nonatomic, copy) NSString *ident;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *path;         // 工作目录
@property (nonatomic, copy) NSString *instruction;  // 项目指令
@property (nonatomic, strong) NSDate *createdAt;
- (NSDictionary *)dictionary;
+ (instancetype)fromDictionary:(NSDictionary *)d;
@end

@interface GMWorkspaceStore : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) NSArray<GMWorkspace *> *workspaces;
@property (nonatomic, readonly, nullable) GMWorkspace *active;

- (GMWorkspace *)addWorkspaceNamed:(NSString *)name path:(NSString *)path;
- (void)updateWorkspace:(GMWorkspace *)ws;
- (void)removeWorkspace:(NSString *)ident;
- (void)activateWorkspace:(NSString *)ident;
- (GMWorkspace *)workspaceWithIdent:(NSString *)ident;
@end
