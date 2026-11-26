// GM Agent · 会话实现：负责 gm/* JSON-RPC 通知 -> 消息模型
#import "GMConversation.h"
#import "GMJSON.h"
#import "GMMessage.h"
#import "GMLog.h"
#import "GMSessionStore.h"

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
        [self configureEngineIfNeeded];
    }
    return self;
}

- (NSArray<GMMessage *> *)messages { return _msgs.copy; }
- (NSString *)currentThreadID { return self.threadID; }

- (void)loadThread:(NSString *)threadID {
    [_msgs removeAllObjects];
    [_toolMessages removeAllObjects];
    _pendingAssistant = nil;
    self.threadID = threadID;
    [[GMSessionStore shared] setCurrentThreadID:threadID];
    if (!threadID.length) { [self.delegate conversationDidChange:self]; return; }

    __weak typeof(self) wself = self;
    [_bridge call:@"gm/thread/history" params:@{@"threadId": threadID} reply:^(id result, NSError *error) {
        __strong typeof(wself) strongSelf = wself;
        if (!strongSelf || error) { [strongSelf.delegate conversationDidChange:strongSelf]; return; }
        NSArray *list = [result isKindOfClass:[NSDictionary class]] ? result[@"messages"] : nil;
        for (NSDictionary *m in list) {
            if (![m isKindOfClass:[NSDictionary class]]) continue;
            NSString *role = m[@"role"];
            NSString *content = m[@"content"];
            if (![content isKindOfClass:[NSString class]]) continue;
            if ([role isEqualToString:@"user"]) {
                [strongSelf.msgs addObject:[GMMessage userText:content]];
            } else if ([role isEqualToString:@"assistant"] && content.length) {
                [strongSelf.msgs addObject:[GMMessage assistantText:content]];
            }
        }
        [strongSelf.delegate conversationDidChange:strongSelf];
    }];
}

// 首次使用：把设置页/内置默认配置推给引擎，否则引擎没有 key 必然 401
- (void)pushConfigToEngine {
    [self configureEngineIfNeeded];
}

- (void)configureEngineIfNeeded {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *base = [d stringForKey:@"gm.baseURL"];
    NSString *key = [d stringForKey:@"gm.apiKey"];
    if (!base.length) base = @"https://api.openai.com/v1/chat/completions";
    if (!key.length) {
        GMLog(@"未配置 API Key");
        return;
    }
    [self.bridge call:@"gm/config" params:@{@"baseURL": base, @"apiKey": key, @"model": self.model ?: @"gpt-5.2"}
                reply:^(id r, NSError *e) {
        if (e) NSLog(@"[GM] 配置引擎失败: %@", e.localizedDescription);
    }];
}

- (void)_push:(GMMessage *)m {
    [_msgs addObject:m];
    [self.delegate conversationDidChange:self];
}

// 把引擎/HTTP 的英文错误转成可读提示
static NSString *GMFriendlyError(NSString *raw) {
    if (!raw.length) return @"未知错误";
    if ([raw containsString:@"401"]) return @"API Key 无效或已过期\n\n请在「设置」重新填写 Key。";
    if ([raw containsString:@"403"]) return @"访问被拒绝（403）\n\n可能是 Key 权限不足或地区限制。";
    if ([raw containsString:@"404"]) return @"接口地址不存在（404）\n\n请检查网关地址是否含 /v1。";
    if ([raw containsString:@"429"]) return @"请求过于频繁（429）\n\n请稍后再试，或检查账户额度。";
    if ([raw containsString:@"500"] || [raw containsString:@"502"] || [raw containsString:@"503"])
        return [NSString stringWithFormat:@"服务端异常\n\n%@", raw];
    if ([raw containsString:@"model"]) {
        return [NSString stringWithFormat:@"模型不可用\n\n%@\n\n请在「设置」点「模型」重新选择。", raw];
    }
    if ([raw containsString:@"DNS"] || [raw containsString:@"域名解析"])
        return [NSString stringWithFormat:@"域名解析失败\n\n请检查网关地址，需形如\nhttps://api.deepseek.com/v1\n\n%@", raw];
    if ([raw containsString:@"TLS"] || [raw containsString:@"SSL"])
        return [NSString stringWithFormat:@"TLS 握手失败\n\n可能是网络被干扰，或网关不支持该协议。\n\n%@", raw];
    if ([raw containsString:@"TCP"])
        return [NSString stringWithFormat:@"无法连接服务器\n\n请检查网络与网关地址。\n\n%@", raw];
    if ([raw containsString:@"没有可用的 shell"])
        return @"找不到可执行 shell\n\n当前环境缺少 bash，请确认安装包完整。";
    return raw;
}

- (void)_fail:(NSString *)msg {
    NSString *friendly = GMFriendlyError(msg);
    GMLog(@"错误: %@", msg);
    dispatch_async(dispatch_get_main_queue(), ^{ [self.delegate conversation:self didFail:friendly]; });
}

#pragma mark - 对外

- (void)sendUserText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) return;
    [self _push:[GMMessage userText:trimmed]];

    /* 每轮都重推配置：避免"设置没生效"这类问题 */
    [self configureEngineIfNeeded];

    /* 首条消息作为会话标题 */
    if (self.msgs.count == 1 && self.threadID.length) {
        NSString *title = trimmed.length > 20 ? [trimmed substringToIndex:20] : trimmed;
        [[GMSessionStore shared] updateSession:self.threadID title:title];
    }
    if (self.threadID.length) [[GMSessionStore shared] touchSession:self.threadID];

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
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        NSMutableDictionary *tp = [NSMutableDictionary dictionary];
        tp[@"threadId"] = tid;
        tp[@"input"] = @[input];
        tp[@"attributes"] = attrs;
        tp[@"text"] = trimmed;
        tp[@"model"] = self.model ?: @"";
        NSString *b2 = [ud stringForKey:@"gm.baseURL"];
        NSString *k2 = [ud stringForKey:@"gm.apiKey"];
        if (b2.length) tp[@"baseURL"] = b2;
        if (k2.length) tp[@"apiKey"] = k2;
        [strongSelf.bridge call:@"gm/turn/start"
                         params:tp
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
    NSMutableDictionary *sp = [NSMutableDictionary dictionary];
    if (self.threadID.length) sp[@"threadId"] = self.threadID;
    [self.bridge call:@"gm/thread/start" params:(sp.count ? sp : nil) reply:^(id result, NSError *error) {
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
    [[GMSessionStore shared] setCurrentThreadID:nil];
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
        _pendingAssistant = nil;
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
