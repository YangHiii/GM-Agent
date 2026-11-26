// GM Agent · 轻量 Markdown 渲染器
// 支持：``` 代码块 ```、`行内代码`、**粗体**、*斜体*、#~###### 标题、- 列表、| 表格 |、> 引用、--- 分隔线
#import "GMMarkdown.h"

static const CGFloat kBodySize = 15.0;
static const CGFloat kCodeSize = 12.5;

@implementation GMMarkdown

+ (UIFont *)bodyFont { return [UIFont systemFontOfSize:kBodySize]; }
+ (UIFont *)boldFont { return [UIFont systemFontOfSize:kBodySize weight:UIFontWeightSemibold]; }
+ (UIFont *)codeFont { return [UIFont monospacedSystemFontOfSize:kCodeSize weight:UIFontWeightRegular]; }

+ (UIColor *)codeBg {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.08]
            : [UIColor colorWithWhite:0.0 alpha:0.05];
    }];
}

+ (UIColor *)quoteColor { return UIColor.secondaryLabelColor; }

/// 行内解析：`code`、**bold**、*italic*
+ (NSAttributedString *)inline:(NSString *)text base:(UIFont *)base color:(UIColor *)color {
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
    NSMutableString *buf = [NSMutableString string];
    NSUInteger i = 0, n = text.length;

    void (^flush)(void) = ^{
        if (!buf.length) return;
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:buf attributes:@{
            NSFontAttributeName: base,
            NSForegroundColorAttributeName: color,
        }]];
        [buf setString:@""];
    };

    while (i < n) {
        unichar c = [text characterAtIndex:i];

        // 行内代码
        if (c == '`') {
            NSRange r = [text rangeOfString:@"`" options:0 range:NSMakeRange(i + 1, n - i - 1)];
            if (r.location != NSNotFound) {
                flush();
                NSString *code = [text substringWithRange:NSMakeRange(i + 1, r.location - i - 1)];
                [out appendAttributedString:[[NSAttributedString alloc] initWithString:code attributes:@{
                    NSFontAttributeName: [self codeFont],
                    NSForegroundColorAttributeName: UIColor.labelColor,
                    NSBackgroundColorAttributeName: [self codeBg],
                }]];
                i = r.location + 1;
                continue;
            }
        }

        // 粗体 **x**
        if (c == '*' && i + 1 < n && [text characterAtIndex:i + 1] == '*') {
            NSRange r = [text rangeOfString:@"**" options:0 range:NSMakeRange(i + 2, n - i - 2)];
            if (r.location != NSNotFound) {
                flush();
                NSString *inner = [text substringWithRange:NSMakeRange(i + 2, r.location - i - 2)];
                [out appendAttributedString:[self inline:inner base:[self boldFont] color:color]];
                i = r.location + 2;
                continue;
            }
        }

        // 斜体 *x*
        if (c == '*' && i + 1 < n && [text characterAtIndex:i + 1] != '*') {
            NSRange r = [text rangeOfString:@"*" options:0 range:NSMakeRange(i + 1, n - i - 1)];
            if (r.location != NSNotFound && r.location > i + 1) {
                flush();
                NSString *inner = [text substringWithRange:NSMakeRange(i + 1, r.location - i - 1)];
                UIFont *it = [UIFont italicSystemFontOfSize:kBodySize];
                [out appendAttributedString:[[NSAttributedString alloc] initWithString:inner attributes:@{
                    NSFontAttributeName: it, NSForegroundColorAttributeName: color,
                }]];
                i = r.location + 1;
                continue;
            }
        }

        [buf appendFormat:@"%C", c];
        i++;
    }
    flush();
    return out;
}

+ (NSArray<NSString *> *)extractCodeBlocks:(NSString *)markdown {
    NSMutableArray *out = [NSMutableArray array];
    if (!markdown.length) return out;
    NSArray *lines = [markdown componentsSeparatedByString:@"\n"];
    NSMutableArray *cur = nil;
    for (NSString *line in lines) {
        if ([line hasPrefix:@"```"]) {
            if (cur) {
                [out addObject:[cur componentsJoinedByString:@"\n"]];
                cur = nil;
            } else {
                cur = [NSMutableArray array];
            }
            continue;
        }
        if (cur) [cur addObject:line];
    }
    if (cur.count) [out addObject:[cur componentsJoinedByString:@"\n"]];
    return out;
}

+ (NSAttributedString *)render:(NSString *)markdown {
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
    if (!markdown.length) return out;

    NSArray<NSString *> *lines = [markdown componentsSeparatedByString:@"\n"];
    BOOL inCode = NO;
    NSMutableArray<NSString *> *codeBuf = [NSMutableArray array];
    NSMutableArray<NSString *> *tableBuf = [NSMutableArray array];

    void (^append)(NSAttributedString *) = ^(NSAttributedString *a) {
        [out appendAttributedString:a];
    };

    void (^flushTable)(void) = ^{
        if (!tableBuf.count) return;
        // 表格：整块等宽 + 灰底，保留对齐
        NSString *blk = [tableBuf componentsJoinedByString:@"\n"];
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:blk attributes:@{
            NSFontAttributeName: [self codeFont],
            NSForegroundColorAttributeName: UIColor.labelColor,
            NSBackgroundColorAttributeName: [self codeBg],
        }]];
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:
                                     @{NSFontAttributeName: [self bodyFont]}]];
        [tableBuf removeAllObjects];
    };

    void (^flushCode)(void) = ^{
        if (!codeBuf.count) return;
        NSString *code = [codeBuf componentsJoinedByString:@"\n"];
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:code attributes:@{
            NSFontAttributeName: [self codeFont],
            NSForegroundColorAttributeName: UIColor.labelColor,
            NSBackgroundColorAttributeName: [self codeBg],
        }]];
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:
                                     @{NSFontAttributeName: [self bodyFont]}]];
        [codeBuf removeAllObjects];
    };

    for (NSUInteger li = 0; li < lines.count; li++) {
        NSString *line = lines[li];

        // 代码围栏
        if ([line hasPrefix:@"```"]) {
            if (inCode) { flushCode(); inCode = NO; }
            else { flushTable(); inCode = YES; }
            continue;
        }
        if (inCode) { [codeBuf addObject:line]; continue; }

        // 表格行
        if ([line hasPrefix:@"|"] && [line containsString:@"|"]) {
            [tableBuf addObject:line];
            continue;
        } else {
            flushTable();
        }

        // 分隔线
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length >= 3 &&
            [[trimmed stringByReplacingOccurrencesOfString:@"-" withString:@""] length] == 0) {
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"──────────\n"
                                                                        attributes:@{
                NSFontAttributeName: [self bodyFont],
                NSForegroundColorAttributeName: UIColor.tertiaryLabelColor,
            }]];
            continue;
        }

        // 标题
        NSUInteger hashes = 0;
        while (hashes < line.length && hashes < 6 &&
               [line characterAtIndex:hashes] == '#') hashes++;
        if (hashes > 0 && hashes < line.length && [line characterAtIndex:hashes] == ' ') {
            NSString *title = [line substringFromIndex:hashes + 1];
            CGFloat size = hashes == 1 ? 19 : (hashes == 2 ? 17 : 15.5);
            UIFont *f = [UIFont systemFontOfSize:size weight:UIFontWeightBold];
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:
                                         [title stringByAppendingString:@"\n"] attributes:@{
                NSFontAttributeName: f,
                NSForegroundColorAttributeName: UIColor.labelColor,
            }]];
            continue;
        }

        // 引用
        if ([trimmed hasPrefix:@">"]) {
            NSString *q = [[trimmed substringFromIndex:1]
                           stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSMutableAttributedString *qa = [[self inline:q base:[self bodyFont] color:[self quoteColor]] mutableCopy];
            [qa appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:
                                        @{NSFontAttributeName: [self bodyFont]}]];
            [out appendAttributedString:qa];
            continue;
        }

        // 列表项
        if (([trimmed hasPrefix:@"- "] || [trimmed hasPrefix:@"* "] || [trimmed hasPrefix:@"+ "])) {
            NSString *item = [trimmed substringFromIndex:2];
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"  •  " attributes:@{
                NSFontAttributeName: [self bodyFont],
                NSForegroundColorAttributeName: UIColor.secondaryLabelColor,
            }]];
            [out appendAttributedString:[self inline:item base:[self bodyFont] color:UIColor.labelColor]];
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:
                                         @{NSFontAttributeName: [self bodyFont]}]];
            continue;
        }

        // 有序列表
        NSRange dot = [trimmed rangeOfString:@". "];
        if (dot.location != NSNotFound && dot.location <= 3) {
            BOOL allDigits = YES;
            for (NSUInteger k = 0; k < dot.location; k++) {
                unichar c = [trimmed characterAtIndex:k];
                if (c < '0' || c > '9') { allDigits = NO; break; }
            }
            if (allDigits) {
                NSString *num = [trimmed substringToIndex:dot.location];
                NSString *item = [trimmed substringFromIndex:dot.location + 2];
                [out appendAttributedString:[[NSAttributedString alloc] initWithString:
                                             [NSString stringWithFormat:@"  %@. ", num] attributes:@{
                    NSFontAttributeName: [self bodyFont],
                    NSForegroundColorAttributeName: UIColor.secondaryLabelColor,
                }]];
                [out appendAttributedString:[self inline:item base:[self bodyFont] color:UIColor.labelColor]];
                [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:
                                             @{NSFontAttributeName: [self bodyFont]}]];
                continue;
            }
        }

        // 普通段落
        if (trimmed.length == 0) {
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:
                                         @{NSFontAttributeName: [self bodyFont]}]];
        } else {
            [out appendAttributedString:[self inline:line base:[self bodyFont] color:UIColor.labelColor]];
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:
                                         @{NSFontAttributeName: [self bodyFont]}]];
        }
    }
    if (inCode) flushCode();
    flushTable();

    // 段落样式：行距
    NSMutableParagraphStyle *ps = [[NSMutableParagraphStyle alloc] init];
    [ps setLineSpacing:2.5];
    [out addAttribute:NSParagraphStyleAttributeName value:ps
                range:NSMakeRange(0, out.length)];
    return out;
}

@end
