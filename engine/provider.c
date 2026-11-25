/* GM Agent · 模型提供方客户端
 * 支持 OpenAI 兼容的 /chat/completions 流式协议（gpt-5.x / openrouter / 自建网关通用）
 */
#include "gm_engine.h"
#include "http.h"
#include "sse.h"
#include <stdio.h>
#include <string.h>

typedef struct {
    GMArena arena;          /* 跨 SSE 帧存活 */
    GMHttpResp *resp;   /* 用于判断 status，捕获错误体 */
    char errbuf[4096];
    size_t errlen;
    GMDeltaFn on_delta;
    void *dctx;
    GMToolCallFn on_tool;
    void *tctx;
    /* tool_calls 聚合（按 index） */
    char *tc_id[16];
    char *tc_name[16];
    GMBuf tc_args[16];
    void *sse;
    int tc_count;
    int done;
    char finish_reason[32];
    double usage_in, usage_out;
    int saw_error;
    char error_msg[512];
} StreamCtx;

static void http_body_cb(void *ctx, const char *data, size_t len) {
    StreamCtx *c = (StreamCtx *)ctx;
    int status = c->resp ? gm_http_resp_status(c->resp) : 200;
    if (status >= 400) {
        /* 只收集错误响应体，供 UI 显示 */
        size_t n = len;
        if (c->errlen + n > sizeof(c->errbuf) - 1) n = sizeof(c->errbuf) - 1 - c->errlen;
        if (n) {
            memcpy(c->errbuf + c->errlen, data, n);
            c->errlen += n;
            c->errbuf[c->errlen] = 0;
        }
        return;
    }
    gm_sse_feed((GMSseParser *)c->sse, data, len);
}

static void sse_data(void *ctx, const char *data, size_t len) {
    StreamCtx *c = (StreamCtx *)ctx;
    if (!data) { c->done = 1; return; }
    GMPVal *v = gm_parse(&c->arena, data, len);
    if (!v || v->t != GM_OBJ) return;

    GMPVal *err = gm_obj_get(v, "error");
    if (err) {
        const char *msg = gm_str(gm_obj_get(err, "message"));
        snprintf(c->error_msg, sizeof(c->error_msg), "%s", msg ? msg : "provider error");
        c->saw_error = 1;
        c->done = 1;
        return;
    }

    GMPVal *usage = gm_obj_get(v, "usage");
    if (usage) {
        c->usage_in = gm_num(gm_obj_get(usage, "prompt_tokens"), c->usage_in);
        c->usage_out = gm_num(gm_obj_get(usage, "completion_tokens"), c->usage_out);
    }

    GMPVal *choices = gm_obj_get(v, "choices");
    GMPVal *ch0 = gm_arr_at(choices, 0);
    if (!ch0) return;
    const char *fr = gm_str(gm_obj_get(ch0, "finish_reason"));
    if (fr) snprintf(c->finish_reason, sizeof(c->finish_reason), "%s", fr);

    GMPVal *delta = gm_obj_get(ch0, "delta");
    if (!delta) delta = gm_obj_get(ch0, "message");
    if (!delta) return;

    const char *content = gm_str(gm_obj_get(delta, "content"));
    if (content && *content && c->on_delta) c->on_delta(c->dctx, "text", content);

    /* 部分提供方用 reasoning / reasoning_content 字段 */
    const char *reason = gm_str(gm_obj_get(delta, "reasoning_content"));
    if (!reason) reason = gm_str(gm_obj_get(delta, "reasoning"));
    if (reason && *reason && c->on_delta) c->on_delta(c->dctx, "reasoning", reason);

    GMPVal *tcs = gm_obj_get(delta, "tool_calls");
    for (size_t i = 0; i < gm_arr_count(tcs); i++) {
        GMPVal *tc = gm_arr_at(tcs, i);
        double idx = gm_num(gm_obj_get(tc, "index"), (double)i);
        if (idx < 0 || idx >= 16) continue;
        int k = (int)idx;
        if (k + 1 > c->tc_count) c->tc_count = k + 1;
        const char *id = gm_str(gm_obj_get(tc, "id"));
        if (id && !c->tc_id[k]) {
            size_t n = strlen(id);
            c->tc_id[k] = malloc(n + 1);
            if (c->tc_id[k]) memcpy(c->tc_id[k], id, n + 1);
        }
        GMPVal *fn = gm_obj_get(tc, "function");
        if (fn) {
            const char *name = gm_str(gm_obj_get(fn, "name"));
            if (name && !c->tc_name[k]) {
                size_t n = strlen(name);
                c->tc_name[k] = malloc(n + 1);
                if (c->tc_name[k]) memcpy(c->tc_name[k], name, n + 1);
            }
            const char *args = gm_str(gm_obj_get(fn, "arguments"));
            if (args && c->tc_args[k].arena) gm_buf_append(&c->tc_args[k], args, strlen(args));
        }
    }
}

int gm_provider_chat(const GMProvider *p, const char *body_json,
                     GMDeltaFn on_delta, void *dctx,
                     GMToolCallFn on_tool, void *tctx,
                     char *finish_reason_out, size_t fro_cap,
                     double *in_tokens, double *out_tokens,
                     char **err_out) {
    if (err_out) *err_out = NULL;
    StreamCtx c;
    memset(&c, 0, sizeof(c));
    gm_arena_init(&c.arena, 2 * 1024 * 1024);
    c.on_delta = on_delta;
    c.dctx = dctx;
    c.on_tool = on_tool;
    c.tctx = tctx;
    for (int i = 0; i < 16; i++) gm_buf_init(&c.tc_args[i], &c.arena, 256);

    GMSseParser sse;
    gm_sse_init(&sse, sse_data, &c);
    c.sse = &sse;

    GMHttpReq req;
    memset(&req, 0, sizeof(req));
    req.method = "POST";
    req.url = p->base_url;
    req.bearer = p->api_key;
    req.body = body_json;
    req.body_len = strlen(body_json);
    req.extra_headers = "Accept: text/event-stream\r\n";
    req.timeout_sec = 300;

    GMHttpResp resp;
    c.resp = &resp;
    /* 打印请求体前缀，便于诊断 400 */
    fprintf(stderr, "[gm] POST %s\n[gm] body: %.600s\n", p->base_url, body_json);
    int rc = gm_http_perform(&req, &resp, http_body_cb, &c);

    gm_sse_finish(&sse);
    gm_arena_reset(&c.arena);
    /* NOTE: arena 在下面还要用，先不释放 */

    int failed = 0;
    if (rc != 0) {
        failed = 1;
        if (err_out) {
            char *e = malloc(strlen(resp.error) + 1);
            if (e) strcpy(e, resp.error);
            *err_out = e;
        }
    } else if (resp.status >= 400) {
        failed = 1;
        if (err_out) {
            char tmp[4600];
            if (c.errlen) {
                snprintf(tmp, sizeof(tmp), "HTTP %d\n%s", resp.status, c.errbuf);
            } else {
                snprintf(tmp, sizeof(tmp), "HTTP %d（服务器无响应体）", resp.status);
            }
            char *e = malloc(strlen(tmp) + 1);
            if (e) strcpy(e, tmp);
            *err_out = e;
        }
    } else if (c.saw_error) {
        failed = 1;
        if (err_out) {
            char *e = malloc(strlen(c.error_msg) + 1);
            if (e) strcpy(e, c.error_msg);
            *err_out = e;
        }
    }

    if (finish_reason_out) snprintf(finish_reason_out, fro_cap, "%s", c.finish_reason);
    if (in_tokens) *in_tokens = c.usage_in;
    if (out_tokens) *out_tokens = c.usage_out;

    if (!failed && on_tool) {
        for (int i = 0; i < c.tc_count; i++) {
            if (!c.tc_name[i]) continue;
            on_tool(tctx, c.tc_id[i] ? c.tc_id[i] : "", c.tc_name[i],
                    c.tc_args[i].p ? c.tc_args[i].p : "{}");
        }
    }
    for (int i = 0; i < c.tc_count; i++) {
        free(c.tc_id[i]);
        free(c.tc_name[i]);
    }
    free(resp.headers);
    gm_arena_free(&c.arena);
    return failed ? -1 : 0;
}
