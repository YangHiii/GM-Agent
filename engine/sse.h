/* GM Agent · SSE（Server-Sent Events）增量解析
 * 用于 OpenAI 兼容 /v1/chat/completions 的 stream:true 响应
 */
#ifndef GM_SSE_H
#define GM_SSE_H

#include <stddef.h>

typedef void (*GMSseDataFn)(void *ctx, const char *data, size_t len);

typedef struct GMSseParser {
    char buf[65536];
    size_t len;
    GMSseDataFn on_data;
    void *ctx;
} GMSseParser;

void gm_sse_init(GMSseParser *p, GMSseDataFn fn, void *ctx);
/* 喂入任意长度的分块；内部按行切分，遇到 "data: xxx" 回调。返回 0 正常 */
int gm_sse_feed(GMSseParser *p, const char *data, size_t len);
/* 结束（处理残留） */
void gm_sse_finish(GMSseParser *p);

#endif
