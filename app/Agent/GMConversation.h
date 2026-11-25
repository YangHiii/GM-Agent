// GM Agent · 会话：把 UI 与引擎事件串起来
#import <Foundation/Foundation.h>
#import "GMBridge.h"
#import "GMMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class GMConversation;

@protocol GMConversationDelegate <NSObject>
- (void)conversationDidChange:(GMConversation *)conversation;
- (void)conversation:(GMConversation *)conversation didFail:(NSString *)message;
@end

@interface GMConversation : NSObject <GMBridgeDelegate>
@property (nonatomic, weak) id<GMConversationDelegate> delegate;
@property (nonatomic, readonly) NSArray<GMMessage *> *messages;
@property (nonatomic, copy) NSString *model;       // 形如 gpt-5.2
@property (nonatomic, copy) NSString *effort;      // low | medium | high
@property (nonatomic, copy) NSString *provider;

- (instancetype)initWithBridge:(GMBridge *)bridge;
- (void)sendUserText:(NSString *)text;
- (void)cancelCurrentTurn;
- (void)newThread;
- (void)pushConfigToEngine;
@end

NS_ASSUME_NONNULL_END
