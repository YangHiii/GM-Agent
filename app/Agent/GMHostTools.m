// GM Agent · 宿主工具（引擎同进程回调，用 ObjC 私有 API 实现）
// 提供 open_app：按应用名 / bundle id 打开 App
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "GMLog.h"

#include <string.h>
#include <stdlib.h>

// LSApplicationWorkspace 私有接口
@interface LSApplicationProxy : NSObject
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSString *applicationIdentifier;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allApplications;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID;
@end

int GMHostToolDispatch(const char *name, const char *args_json, char **out);

static NSString *ExtractName(const char *args_json) {
    if (!args_json) return nil;
    NSString *s = [NSString stringWithUTF8String:args_json];
    if (!s.length) return nil;
    NSRange r = [s rangeOfString:@"\"name\""];
    if (r.location == NSNotFound) return nil;
    NSString *tail = [s substringFromIndex:r.location + r.length];
    NSRange q1 = [tail rangeOfString:@"\""];
    if (q1.location == NSNotFound) return nil;
    tail = [tail substringFromIndex:q1.location + 1];
    NSRange q2 = [tail rangeOfString:@"\""];
    if (q2.location == NSNotFound) return nil;
    return [tail substringToIndex:q2.location];
}

static void SetOut(char **out, NSString *msg) {
    if (!out) return;
    *out = strdup(msg.UTF8String ?: "");
}

static int GMOpenApp(const char *args_json, char **out) {
    NSString *want = ExtractName(args_json);
    if (!want.length) { SetOut(out, @"缺少 name 参数"); return 1; }
    GMLog(@"open_app: %@", want);

    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!wsClass) { SetOut(out, @"LSApplicationWorkspace 不可用（需要越狱/私有 API）"); return 2; }
    id ws = ((id (*)(id, SEL))objc_msgSend)(wsClass, @selector(defaultWorkspace));
    if (!ws) { SetOut(out, @"无法获取 workspace"); return 3; }

    SEL openSel = NSSelectorFromString(@"openApplicationWithBundleID:");
    if ([want containsString:@"."] && ![want containsString:@" "]) {
        if ([ws respondsToSelector:openSel]) {
            BOOL ok = ((BOOL (*)(id, SEL, id))objc_msgSend)(ws, openSel, want);
            if (ok) { SetOut(out, [NSString stringWithFormat:@"已打开 %@", want]); return 0; }
        }
    }

    SEL allSel = NSSelectorFromString(@"allApplications");
    if ([ws respondsToSelector:allSel]) {
        NSArray *apps = ((id (*)(id, SEL))objc_msgSend)(ws, allSel);
        LSApplicationProxy *best = nil;
        for (LSApplicationProxy *p in apps) {
            NSString *n = [p respondsToSelector:@selector(localizedName)] ? [p localizedName] : nil;
            if (!n.length) continue;
            if ([n isEqualToString:want]) { best = p; break; }
            if (!best && [n containsString:want]) best = p;
        }
        if (!best) {
            for (LSApplicationProxy *p in apps) {
                NSString *n = [p respondsToSelector:@selector(localizedName)] ? [p localizedName] : nil;
                if (n.length > 1 && [want containsString:n]) { best = p; break; }
            }
        }
        if (best) {
            NSString *bid = [best respondsToSelector:@selector(bundleIdentifier)] ? [best bundleIdentifier] : nil;
            if (!bid.length && [best respondsToSelector:@selector(applicationIdentifier)])
                bid = [best applicationIdentifier];
            if (bid.length && [ws respondsToSelector:openSel]) {
                BOOL ok = ((BOOL (*)(id, SEL, id))objc_msgSend)(ws, openSel, bid);
                if (ok) {
                    SetOut(out, [NSString stringWithFormat:@"已打开 %@（%@）", want, bid]);
                    return 0;
                }
            }
        }
    }
    SetOut(out, [NSString stringWithFormat:@"未找到应用「%@」", want]);
    return 4;
}

int GMHostToolDispatch(const char *name, const char *args_json, char **out) {
    if (!name) return -1;
    if (strcmp(name, "open_app") == 0) return GMOpenApp(args_json, out);
    return -1;
}
