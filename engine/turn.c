/* GM Agent · 对话回合：拼请求 -> 流式 -> 工具循环 -> 事件推送
 *
 * 对外（stdio JSON-RPC 通知）：
 *   gm/event/delta   {kind: text|reasoning, delta}
 *   gm/event/toolCall{id, name, summary}
 *   gm/event/toolResult{id, output, code}
 *   gm/event/turnEnd {finish, usage}
 */
#include "gm_engine.h"
#include <unistd.h>

extern void gm_emit(GMArena *arena, GMPVal *msg);   /* main.c 提供 */

#define MAX_TOOL_ROUNDS 8

typedef struct {
    GMArena *arena;
    GMBuf text;
    GMBuf reasoning;
    int any;
    /* 待执行工具 */
    int tc_count;
    char *tc_id[8];
    char *tc_name[8];
    GMBuf tc_args[8];
    char *tc_out[8];
    GMArena outArena;   /* 事件输出专用：每次 emit 后 reset，不碰轮次 arena */
} TurnCtx;

static void on_delta(void *ctx, const char *kind, const char *delta) {
    TurnCtx *t = (TurnCtx *)ctx;
    if (!delta) return;
    t->any = 1;
    if (strcmp(kind, "reasoning") == 0) gm_buf_append(&t->reasoning, delta, strlen(delta));
    else gm_buf_append(&t->text, delta, strlen(delta));

    GMArena *o = &t->outArena;  /* 事件专用区，emit 后由 main 的 g_out 序列化，互不干扰 */
    GMPVal *n = gm_val_obj(o);
    GMPVal *params = gm_val_obj(o);
    gm_obj_set(o, params, "kind", gm_val_str(o, kind));
    gm_obj_set(o, params, "delta", gm_val_str(o, delta));
    gm_obj_set(o, n, "method", gm_val_str(o, "gm/event/delta"));
    gm_obj_set(o, n, "params", params);
    gm_emit(o, n);
}

static void on_tool(void *ctx, const char *id, const char *name, const char *args) {
    TurnCtx *t = (TurnCtx *)ctx;
    if (t->tc_count >= 8) return;
    int k = t->tc_count++;
    t->tc_id[k] = strdup(id ? id : "");
    t->tc_name[k] = strdup(name ? name : "");
    gm_buf_init(&t->tc_args[k], t->arena, 512);
    gm_buf_puts(&t->tc_args[k], args ? args : "{}");
}

int gm_turn_run(GMArena *arena, const GMProvider *prov, GMSession *session,
                const char *user_text, const char *system_prompt) {
    TurnCtx t;
    memset(&t, 0, sizeof(t));
    t.arena = arena;
    gm_arena_init(&t.outArena, 4 * 1024 * 1024);
    gm_buf_init(&t.text, arena, 4096);
    gm_buf_init(&t.reasoning, arena, 1024);

    /* messages 数组：system + 历史（此处简化为单轮，历史由 session 落盘） */
    GMPVal *messages = gm_val_arr(arena);
    if (system_prompt && *system_prompt) {
        GMPVal *m = gm_val_obj(arena);
        gm_obj_set(arena, m, "role", gm_val_str(arena, "system"));
        gm_obj_set(arena, m, "content", gm_val_str(arena, system_prompt));
        gm_arr_push(arena, messages, m);
    }
    GMPVal *um = gm_val_obj(arena);
    gm_obj_set(arena, um, "role", gm_val_str(arena, "user"));
    gm_obj_set(arena, um, "content", gm_val_str(arena, user_text ? user_text : ""));
    gm_arr_push(arena, messages, um);

    GMPVal *tools = gm_tool_specs(arena);

    extern int gm_turn_cancelled(void);
    for (int round = 0; round < MAX_TOOL_ROUNDS; round++) {
        if (gm_turn_cancelled()) {
            GMPVal *cn = gm_val_obj(arena);
            GMPVal *cp = gm_val_obj(arena);
            gm_obj_set(arena, cp, "finish", gm_val_str(arena, "cancelled"));
            gm_obj_set(arena, cn, "method", gm_val_str(arena, "gm/event/turnEnd"));
            gm_obj_set(arena, cn, "params", cp);
            gm_emit(arena, cn);
            return 0;
        }
        /* 拼 body */
        GMArena bodyArena;
        gm_arena_init(&bodyArena, 4 * 1024 * 1024);
        GMPVal *body = gm_val_obj(&bodyArena);
        gm_obj_set(&bodyArena, body, "model", gm_val_str(&bodyArena, prov->model));
        gm_obj_set(&bodyArena, body, "stream", gm_val_true(&bodyArena, 1));
        gm_obj_set(&bodyArena, body, "messages", messages);
        gm_obj_set(&bodyArena, body, "tools", tools);
        GMBuf bj;
        gm_buf_init(&bj, &bodyArena, 4096);
        gm_write_val(&bj, body);

        t.any = 0;
        t.tc_count = 0;
        char finish[64] = {0};
        double tin = 0, tout = 0;
        char *err = NULL;
        int rc = gm_provider_chat(prov, bj.p, on_delta, &t, on_tool, &t, finish, sizeof(finish),
                                  &tin, &tout, &err);

        /* 部分模型（如 deepseek-reasoner）不支持 tools：
           若返回 400 且错误体提到 tool/function，自动去掉 tools 重试一次 */
        if (rc != 0 && err && strstr(err, "400") &&
            (strstr(err, "tool") || strstr(err, "function") || strstr(err, "Tool"))) {
            fprintf(stderr, "[gm] 模型不支持 tools，去掉后重试\n");
            GMArena body2;
            gm_arena_init(&body2, 4 * 1024 * 1024);
            GMPVal *b2 = gm_val_obj(&body2);
            gm_obj_set(&body2, b2, "model", gm_val_str(&body2, prov->model));
            gm_obj_set(&body2, b2, "stream", gm_val_true(&body2, 1));
            gm_obj_set(&body2, b2, "messages", messages);
            GMBuf bj2;
            gm_buf_init(&bj2, &body2, 4096);
            gm_write_val(&bj2, b2);

            t.any = 0;
            t.tc_count = 0;
            finish[0] = 0;
            tin = tout = 0;
            free(err);
            err = NULL;
            rc = gm_provider_chat(prov, bj2.p, on_delta, &t, on_tool, &t, finish, sizeof(finish),
                                  &tin, &tout, &err);
            gm_arena_free(&body2);
        }
        gm_arena_free(&bodyArena);

        if (rc != 0) {
            GMPVal *n = gm_val_obj(arena);
            GMPVal *params = gm_val_obj(arena);
            gm_obj_set(arena, params, "message", gm_val_str(arena, err ? err : "请求失败"));
            gm_obj_set(arena, n, "method", gm_val_str(arena, "gm/event/error"));
            gm_obj_set(arena, n, "params", params);
            gm_emit(arena, n);
            free(err);
            return -1;
        }

        if (t.tc_count == 0) {
            if (session && t.text.p) gm_session_append_assistant(session, t.text.p);
            GMPVal *n = gm_val_obj(arena);
            GMPVal *params = gm_val_obj(arena);
            gm_obj_set(arena, params, "finish", gm_val_str(arena, finish));
            gm_obj_set(arena, params, "inputTokens", gm_val_num(arena, tin));
            gm_obj_set(arena, params, "outputTokens", gm_val_num(arena, tout));
            gm_obj_set(arena, n, "method", gm_val_str(arena, "gm/event/turnEnd"));
            gm_obj_set(arena, n, "params", params);
            gm_emit(arena, n);
            return 0;
        }

        /* 有工具调用：逐个执行，回填 assistant + tool 消息 */
        GMPVal *am = gm_val_obj(arena);
        gm_obj_set(arena, am, "role", gm_val_str(arena, "assistant"));
        if (t.text.p && t.text.len) gm_obj_set(arena, am, "content", gm_val_str(arena, t.text.p));
        GMPVal *tcs = gm_val_arr(arena);
        for (int i = 0; i < t.tc_count; i++) {
            GMPVal *tc = gm_val_obj(arena);
            gm_obj_set(arena, tc, "id", gm_val_str(arena, t.tc_id[i]));
            gm_obj_set(arena, tc, "type", gm_val_str(arena, "function"));
            GMPVal *fn = gm_val_obj(arena);
            gm_obj_set(arena, fn, "name", gm_val_str(arena, t.tc_name[i]));
            gm_obj_set(arena, fn, "arguments", gm_val_str(arena, t.tc_args[i].p ? t.tc_args[i].p : "{}"));
            gm_obj_set(arena, tc, "function", fn);
            gm_arr_push(arena, tcs, tc);
        }
        gm_obj_set(arena, am, "tool_calls", tcs);
        gm_arr_push(arena, messages, am);

        for (int i = 0; i < t.tc_count; i++) {
            /* 通知 UI：开始执行 */
            GMPVal *n = gm_val_obj(arena);
            GMPVal *params = gm_val_obj(arena);
            gm_obj_set(arena, params, "id", gm_val_str(arena, t.tc_id[i]));
            gm_obj_set(arena, params, "name", gm_val_str(arena, t.tc_name[i]));
            gm_obj_set(arena, params, "summary", gm_val_str(arena, t.tc_args[i].p ? t.tc_args[i].p : ""));
            gm_obj_set(arena, n, "method", gm_val_str(arena, "gm/event/toolCall"));
            gm_obj_set(arena, n, "params", params);
            gm_emit(arena, n);

            /* 解析参数 */
            char command[1024] = {0}, cwd[512] = {0};
            /* 参数解析用独立 arena：回合 arena 不能回退，否则会覆盖后续构造的对象 */
            GMArena argArena;
            gm_arena_init(&argArena, 256 * 1024);
            GMPVal *args = gm_parse(&argArena, t.tc_args[i].p ? t.tc_args[i].p : "{}",
                                    t.tc_args[i].p ? strlen(t.tc_args[i].p) : 2);
            const char *cc = args ? gm_str(gm_obj_get(args, "command")) : NULL;
            const char *cw = args ? gm_str(gm_obj_get(args, "cwd")) : NULL;
            if (cc) snprintf(command, sizeof(command), "%s", cc);
            if (cw) snprintf(cwd, sizeof(cwd), "%s", cw);
            gm_arena_free(&argArena);

            int code = 0;
            char *out = NULL;
            if (strcmp(t.tc_name[i], "open_app") == 0) {
                GMHostToolFn host = gm_host_tool_handler();
                char *hostOut = NULL;
                int hrc = host ? host("open_app", t.tc_args[i].p ? t.tc_args[i].p : "{}", &hostOut) : -2;
                if (hrc == -2) {
                    out = strdup("当前环境不支持打开应用（宿主未注册该能力）");
                    code = 1;
                } else {
                    out = hostOut ? hostOut : strdup(hrc == 0 ? "已打开" : "打开失败");
                    code = hrc;
                }
            } else {
                out = gm_tool_run_shell(command, cwd[0] ? cwd : NULL, 120000, &code);
            }
            if (!out) out = strdup("");
            size_t outlen = strlen(out);
            if (outlen > 8000) out[8000] = 0;   /* 回填给模型时截断，避免撑爆上下文 */

            GMPVal *n2 = gm_val_obj(arena);
            GMPVal *p2 = gm_val_obj(arena);
            gm_obj_set(arena, p2, "id", gm_val_str(arena, t.tc_id[i]));
            gm_obj_set(arena, p2, "output", gm_val_str(arena, out));
            gm_obj_set(arena, p2, "code", gm_val_num(arena, code));
            gm_obj_set(arena, n2, "method", gm_val_str(arena, "gm/event/toolResult"));
            gm_obj_set(arena, n2, "params", p2);
            gm_emit(arena, n2);
            /* 输出留存给下一轮回填（arena 内拷贝） */
            {
                size_t ol = strlen(out) > 8000 ? 8000 : strlen(out);
                t.tc_out[i] = (char *)malloc(ol + 1);
                if (t.tc_out[i]) { memcpy(t.tc_out[i], out, ol); t.tc_out[i][ol] = 0; }
            }
            free(out);
        }
        /* 工具结果统一回填（必须在 g_out 复用前完成，否则事件 arena 回退会冲掉消息块） */
        for (int i = 0; i < t.tc_count; i++) {
            GMPVal *rm = gm_val_obj(arena);
            gm_obj_set(arena, rm, "role", gm_val_str(arena, "tool"));
            gm_obj_set(arena, rm, "tool_call_id", gm_val_str(arena, t.tc_id[i]));
            gm_obj_set(arena, rm, "content", gm_val_str(arena, t.tc_out[i] ? t.tc_out[i] : ""));
            gm_arr_push(arena, messages, rm);
        }

        /* 下一轮：让模型基于工具结果继续 */
        gm_buf_init(&t.text, arena, 4096);
        gm_buf_init(&t.reasoning, arena, 1024);
    }

    GMPVal *n = gm_val_obj(arena);
    GMPVal *p = gm_val_obj(arena);
    gm_obj_set(arena, p, "finish", gm_val_str(arena, "max_rounds"));
    gm_obj_set(arena, n, "method", gm_val_str(arena, "gm/event/turnEnd"));
    gm_obj_set(arena, n, "params", p);
    gm_emit(arena, n);
    return 0;
}
