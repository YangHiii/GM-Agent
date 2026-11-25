// GM Agent · 会话实现：负责 gm/* JSON-RPC 通知 -> 消息模型
#import "GMConversation.h"
#import "GMJSON.h"

@interface GMConversation ()
@property (nonatomic, strong) GMBridge *bridge;
@property (nonatomic, strong) NSMutableArray<GMMessage *> *msgs;
@property (nonatomic, copy) NSString *threadID;
@property (nonatomic, strong) GMMessage *pendingAssistant;
@property (nonatomic, strong) NSMutableDictionary<NSString *, GMMessage *> *toolMessages;
@end

@implementation GMConversation

- (instancetype)initWithBridge:(GMBridge *)bridge {
    if ((self = [super init])) {
        _bridge = bridge;
        _bridge.delegate = self;
        _msgs = [NSMutableArray array];
        _toolMessages = [NSMutableDictionary dictionary];
        _model = @"gpt-5.2";
        _effort = @"medium";
        _provider = @"openai";
    }
    return self;
}

- (NSArray<GMMessage *> *)messages { return _msgs.copy; }

- (void)_push:(GMMessage *)m {
    [_msgs addObject:m];
    [self.delegate conversationDidChange:self];
}

- (void)_fail:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{ [self.delegate conversation:self didFail:msg]; });
}

#pragma mark - 对外

- (void)sendUserText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) return;
    [self _push:[GMMessage userText:trimmed]];

    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    attrs[@"model"] = self.model ?: @"";
    attrs[@"reasoning_effort"] = self.effort ?: @"medium";
    attrs[@"provider"] = self.provider ?: @"openai";

    NSDictionary *input = @{@"type": @"text", @"text": trimmed};

    __weak typeof(self) weakSelf = self;
    void (^startTurn)(NSString *) = ^(NSString *tid) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.threadID = tid;
        [strongSelf.bridge call:@"gm/turn/start"
                         params:@{@"threadId": tid, @"input": @[input], @"attributes": attrs}
                          reply:^(id result, NSError *error) {
            if (error) {
                [strongSelf _fail:error.localizedDescription];
            }
        }];
    };

    if (self.threadID.length) {
        startTurn(self.threadID);
        return;
    }
    [self.bridge call:@"gm/thread/start" params:nil reply:^(id result, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error) { [strongSelf _fail:error.localizedDescription]; return; }
        NSString *tid = nil;
        if ([result isKindOfClass:[NSDictionary class]]) {
            id t = result[@"thread"] ?: result;
            if ([t isKindOfClass:[NSDictionary class]]) tid = t[@"id"];
        }
        if (!tid.length) { [strongSelf _fail:@"引擎未返回 thread id"]; return; }
        startTurn(tid);
    }];
}

- (void)cancelCurrentTurn {
    if (!self.threadID.length) return;
    [_bridge call:@"gm/turn/cancel" params:@{@"threadId": self.threadID} reply:nil];
}

- (void)newThread {
    _threadID = nil;
    [_msgs removeAllObjects];
    [_toolMessages removeAllObjects];
    _pendingAssistant = nil;
    [self.delegate conversationDidChange:self];
}

#pragma mark - GMBridgeDelegate

- (void)bridge:(GMBridge *)bridge didReceiveNotification:(NSDictionary *)n {
    NSString *method = n[@"method"];
    NSDictionary *params = [n[@"params"] isKindOfClass:[NSDictionary class]] ? n[@"params"] : @{};
    id item = params[@"item"];

    if ([method isEqualToString:@"gm/event/delta"]) {
        NSString *kind = params[@"kind"] ?: @"text";
        NSString *delta = params[@"delta"] ?: @"";
        if (!_pendingAssistant) {
            _pendingAssistant = [GMMessage assistantText:@""];
            _pendingAssistant.streaming = YES;
            [_msgs addObject:_pendingAssistant];
        }
        if ([kind isEqualToString:@"reasoning"]) {
            _pendingAssistant.reasoning = [_pendingAssistant.reasoning stringByAppendingString:delta] ?: delta;
        } else {
            _pendingAssistant.text = [_pendingAssistant.text stringByAppendingString:delta];
        }
        [self.delegate conversationDidChange:self];
        return;
    }

    if ([method isEqualToString:@"gm/event/toolCall"]) {
        NSString *toolID = params[@"id"] ?: [[NSUUID UUID] UUIDString];
        NSString *name = params[@"name"] ?: @"tool";
        NSString *summary = params[@"summary"] ?: @"";
        GMMessage *m = [GMMessage tool:name summary:summary];
        m.itemID = toolID;
        _toolMessages[toolID] = m;
        [_msgs addObject:m];
        [self.delegate conversationDidChange:self];
        return;
    }

    if ([method isEqualToString:@"gm/event/toolResult"]) {
        NSString *toolID = params[@"id"] ?: @"";
        GMMessage *m = _toolMessages[toolID];
        NSString *out = params[@"output"] ?: @"";
        if (m) {
            m.toolSummary = [NSString stringWithFormat:@"%@\n%@", m.toolSummary ?: @"", out];
        } else {
            GMMessage *t = [GMMessage tool:params[@"name"] ?: @"tool" summary:out];
            [_msgs addObject:t];
        }
        [self.delegate conversationDidChange:self];
        return;
    }

    if ([method isEqualToString:@"gm/event/turnEnd"]) {
        _pendingAssistant.streaming = NO;
        _pendingAssistant = nil;
        [self.delegate conversationDidChange:self];
        return;
    }

    if ([method isEqualToString:@"gm/approval/request"]) {
        NSString *cmd = params[@"command"] ?: @"(未命名命令)";
        GMMessage *t = [GMMessage tool:@"approval" summary:cmd];
        [_msgs addObject:t];
        [self.delegate conversationDidChange:self];
        return;
    }

    if ([method isEqualToString:@"gm/event/error"]) {
        [self _fail:params[@"message"] ?: @"引擎错误"];
    }
}

- (void)bridge:(GMBridge *)bridge didExitWithStatus:(int)status {
    [self _fail:[NSString stringWithFormat:@"引擎已退出（%d）", status]];
}
@end
