// GM Agent · 引擎桥：管理 gm-engine 子进程，提供 stdio JSON-RPC 双向通道
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class GMBridge;

@protocol GMBridgeDelegate <NSObject>
- (void)bridge:(GMBridge *)bridge didReceiveNotification:(NSDictionary *)notification;
- (void)bridge:(GMBridge *)bridge didExitWithStatus:(int)status;
@end

@interface GMBridge : NSObject
+ (instancetype)shared;
@property (nonatomic, weak) id<GMBridgeDelegate> delegate;
@property (nonatomic, readonly) BOOL running;

/// 启动引擎（可执行文件位于 app bundle 的 gm-engine）
- (BOOL)startWithError:(NSError **)error;
- (void)stop;

/// 发送请求；reply 在后台队列回调（可为 nil）
- (void)call:(NSString *)method
      params:(nullable id)params
      reply:(nullable void (^)(id _Nullable result, NSError *_Nullable error))reply;

/// 发送通知（无 id）
- (void)notify:(NSString *)method params:(nullable id)params;
@end

NS_ASSUME_NONNULL_END
