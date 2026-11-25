/* GM Agent · SSE 增量解析实现 */
#include "sse.h"
#include <string.h>
#include <stdlib.h>

static void handle_line(GMSseParser *p, const char *line, size_t n) {
    if (n == 0) return;
    /* 处理多行 data:，按 SSE 规范用 \n 拼接；这里逐行回调，调用方做 JSON 时通常每行一个完整对象 */
    if (n >= 5 && memcmp(line, "data:", 5) == 0) {
        const char *d = line + 5;
        size_t dn = n - 5;
        while (dn && (*d == ' ' || *d == '\t')) { d++; dn--; }
        if (dn == 6 && memcmp(d, "[DONE]", 6) == 0) {
            p->on_data(p->ctx, NULL, 0);   /* 用 NULL 表示结束 */
            return;
        }
        p->on_data(p->ctx, d, dn);
    }
    /* event: / id: / 注释行忽略 */
}

void gm_sse_init(GMSseParser *p, GMSseDataFn fn, void *ctx) {
    p->len = 0;
    p->on_data = fn;
    p->ctx = ctx;
}

int gm_sse_feed(GMSseParser *p, const char *data, size_t len) {
    for (size_t i = 0; i < len; i++) {
        char c = data[i];
        if (c == '\n') {
            size_t n = p->len;
            if (n && p->buf[n - 1] == '\r') n--;
            handle_line(p, p->buf, n);
            p->len = 0;
            if (!p->on_data) return 0;
            continue;
        }
        if (p->len + 1 >= sizeof(p->buf)) {
            /* 单行过长：丢弃，避免溢出 */
            p->len = 0;
            continue;
        }
        p->buf[p->len++] = c;
    }
    return 0;
}

void gm_sse_finish(GMSseParser *p) {
    if (p->len) {
        size_t n = p->len;
        if (n && p->buf[n - 1] == '\r') n--;
        handle_line(p, p->buf, n);
        p->len = 0;
    }
}
