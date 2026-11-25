// GM Agent · JSON 最小实现
#import "GMJSON.h"

static void _GMJSONSkipWS(const unichar *s, NSUInteger len, NSUInteger *i) {
    while (*i < len) {
        unichar c = s[*i];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') { (*i)++; continue; }
        break;
    }
}

static id _GMJSONValue(const unichar *s, NSUInteger len, NSUInteger *i, BOOL *ok);

static NSString *_GMJSONString(const unichar *s, NSUInteger len, NSUInteger *i, BOOL *ok) {
    if (*i >= len || s[*i] != '"') { *ok = NO; return nil; }
    (*i)++;
    NSMutableString *out = [NSMutableString stringWithCapacity:32];
    while (*i < len) {
        unichar c = s[*i];
        if (c == '"') { (*i)++; return out; }
        if (c == '\\') {
            (*i)++;
            if (*i >= len) break;
            unichar e = s[*i];
            switch (e) {
                case '"': [out appendString:@"\""]; break;
                case '\\': [out appendString:@"\\"]; break;
                case '/': [out appendString:@"/"]; break;
                case 'b': [out appendString:@"\b"]; break;
                case 'f': [out appendString:@"\f"]; break;
                case 'n': [out appendString:@"\n"]; break;
                case 'r': [out appendString:@"\r"]; break;
                case 't': [out appendString:@"\t"]; break;
                case 'u': {
                    if (*i + 4 >= len) { *ok = NO; return nil; }
                    unichar u = 0;
                    for (int k = 1; k <= 4; k++) {
                        unichar h = s[*i + k];
                        u <<= 4;
                        if (h >= '0' && h <= '9') u |= (h - '0');
                        else if (h >= 'a' && h <= 'f') u |= (h - 'a' + 10);
                        else if (h >= 'A' && h <= 'F') u |= (h - 'A' + 10);
                        else { *ok = NO; return nil; }
                    }
                    [out appendFormat:@"%C", u];
                    *i += 4;
                    break;
                }
                default: *ok = NO; return nil;
            }
            (*i)++;
            continue;
        }
        [out appendFormat:@"%C", c];
        (*i)++;
    }
    *ok = NO;
    return nil;
}

static id _GMJSONNumber(const unichar *s, NSUInteger len, NSUInteger *i) {
    NSUInteger start = *i;
    if (*i < len && (s[*i] == '-' || s[*i] == '+')) (*i)++;
    while (*i < len && ((s[*i] >= '0' && s[*i] <= '9') || s[*i] == '.' ||
                        s[*i] == 'e' || s[*i] == 'E' || s[*i] == '-' || s[*i] == '+')) (*i)++;
    NSString *num = [NSString stringWithCharacters:s + start length:*i - start];
    if ([num rangeOfString:@"."].location != NSNotFound ||
        [num rangeOfString:@"e"].location != NSNotFound ||
        [num rangeOfString:@"E"].location != NSNotFound) {
        return @([num doubleValue]);
    }
    return @([num longLongValue]);
}

static id _GMJSONValue(const unichar *s, NSUInteger len, NSUInteger *i, BOOL *ok) {
    _GMJSONSkipWS(s, len, i);
    if (*i >= len) { *ok = NO; return nil; }
    unichar c = s[*i];
    if (c == '{') {
        (*i)++;
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        _GMJSONSkipWS(s, len, i);
        if (*i < len && s[*i] == '}') { (*i)++; return d; }
        while (*i < len) {
            _GMJSONSkipWS(s, len, i);
            NSString *k = _GMJSONString(s, len, i, ok);
            if (!*ok) return nil;
            _GMJSONSkipWS(s, len, i);
            if (*i >= len || s[*i] != ':') { *ok = NO; return nil; }
            (*i)++;
            id v = _GMJSONValue(s, len, i, ok);
            if (!*ok) return nil;
            d[k] = v ?: [NSNull null];
            _GMJSONSkipWS(s, len, i);
            if (*i < len && s[*i] == ',') { (*i)++; continue; }
            if (*i < len && s[*i] == '}') { (*i)++; return d; }
            *ok = NO; return nil;
        }
        *ok = NO; return nil;
    }
    if (c == '[') {
        (*i)++;
        NSMutableArray *a = [NSMutableArray array];
        _GMJSONSkipWS(s, len, i);
        if (*i < len && s[*i] == ']') { (*i)++; return a; }
        while (*i < len) {
            id v = _GMJSONValue(s, len, i, ok);
            if (!*ok) return nil;
            [a addObject:v ?: [NSNull null]];
            _GMJSONSkipWS(s, len, i);
            if (*i < len && s[*i] == ',') { (*i)++; continue; }
            if (*i < len && s[*i] == ']') { (*i)++; return a; }
            *ok = NO; return nil;
        }
        *ok = NO; return nil;
    }
    if (c == '"') return _GMJSONString(s, len, i, ok);
    if (c == 't') { if (*i + 4 <= len) { *i += 4; return @YES; } *ok = NO; return nil; }
    if (c == 'f') { if (*i + 5 <= len) { *i += 5; return @NO; } *ok = NO; return nil; }
    if (c == 'n') { if (*i + 4 <= len) { *i += 4; return [NSNull null]; } *ok = NO; return nil; }
    return _GMJSONNumber(s, len, i);
}

id GMJSONParse(NSString *text) {
    if (text.length == 0) return nil;
    NSUInteger len = text.length;
    unichar *buf = malloc(sizeof(unichar) * len);
    if (!buf) return nil;
    [text getCharacters:buf range:NSMakeRange(0, len)];
    NSUInteger i = 0;
    BOOL ok = YES;
    id v = _GMJSONValue(buf, len, &i, &ok);
    free(buf);
    return ok ? v : nil;
}

static void _GMAppendJSON(NSMutableString *out, id obj) {
    if (!obj || obj == [NSNull null]) { [out appendString:@"null"]; return; }
    if ([obj isKindOfClass:[NSString class]]) {
        NSString *s = obj;
        [out appendString:@"\""];
        for (NSUInteger i = 0; i < s.length; i++) {
            unichar c = [s characterAtIndex:i];
            switch (c) {
                case '"': [out appendString:@"\\\""]; break;
                case '\\': [out appendString:@"\\\\"]; break;
                case '\n': [out appendString:@"\\n"]; break;
                case '\r': [out appendString:@"\\r"]; break;
                case '\t': [out appendString:@"\\t"]; break;
                default:
                    if (c < 0x20) [out appendFormat:@"\\u%04x", c];
                    else [out appendFormat:@"%C", c];
            }
        }
        [out appendString:@"\""];
        return;
    }
    if ([obj isKindOfClass:[NSNumber class]]) {
        NSNumber *n = obj;
        const char *t = n.objCType;
        if (strcmp(t, "c") == 0 || strcmp(t, "B") == 0) {   /* char / BOOL */
            [out appendString:n.boolValue ? @"true" : @"false"];
        } else {
            [out appendFormat:@"%@", n];
        }
        return;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        [out appendString:@"["];
        BOOL first = YES;
        for (id e in obj) { if (!first) [out appendString:@","]; first = NO; _GMAppendJSON(out, e); }
        [out appendString:@"]"];
        return;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        [out appendString:@"{"];
        BOOL first = YES;
        for (id k in obj) {
            if (!first) [out appendString:@","];
            first = NO;
            _GMAppendJSON(out, [k description]);
            [out appendString:@":"];
            _GMAppendJSON(out, obj[k]);
        }
        [out appendString:@"}"];
        return;
    }
    _GMAppendJSON(out, [obj description]);
}

NSString *GMJSONString(id obj) {
    NSMutableString *out = [NSMutableString stringWithCapacity:256];
    _GMAppendJSON(out, obj);
    return out;
}
