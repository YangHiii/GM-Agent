/* GM Agent · HTTPS 传输（OpenSSL socket，支持 chunked + SSE 流式回调） */
#ifndef GM_HTTP_H
#define GM_HTTP_H

#include <stddef.h>

/* 返回 0 继续接收；返回 1 客户端主动结束（如收到 SSE [DONE]） */
typedef int (*GMHttpBodyFn)(void *ctx, const char *data, size_t len);

typedef struct GMHttpReq {
    const char *method;        /* "GET" / "POST" */
    const char *url;           /* https://host/path */
    const char *bearer;        /* 可为 NULL */
    const char *extra_headers; /* 每行 "Name: value\r\n"，可为 NULL */
    const char *body;          /* 可为 NULL */
    size_t body_len;
    int timeout_sec;
} GMHttpReq;

typedef struct GMHttpResp {
    int status;
    char *headers;      /* malloc，调用方 free */
    long long content_length;  /* -1 未知（chunked / SSE） */
    int ok;             /* 1 表示拿到响应行 */
    char error[256];
} GMHttpResp;

/* 阻塞请求；body 分块回调（chunked 自动解包）。返回 0 成功 */
int gm_http_perform(const GMHttpReq *req, GMHttpResp *resp, GMHttpBodyFn on_body, void *ctx);

/* 读取响应状态码（供回调中判断是否错误体） */
int gm_http_resp_status(const void *resp);

#endif
