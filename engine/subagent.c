/* GM Agent · 子代理：独立上下文执行一个探索/检索任务 */
#include "gm_engine.h"

static void sg_delta(void *ctx, const char *kind, const char *delta) {
    GMBuf *b = (GMBuf *)ctx;
    if (!b || !delta) return;
    if (strcmp(kind, "text") == 0) gm_buf_append(b, delta, strlen(delta));
}

int gm_subagent_run(const char *task, const char *model, const char *base_url,
                    const char *api_key, char **out, char **err) {
    if (!task || !*task) { if (err) *err = strdup("缺少任务描述"); return -1; }

    GMArena a;
    gm_arena_init(&a, 1024 * 1024);
    if (!a.p) { if (err) *err = strdup("内存不足"); return -1; }

    GMPVal *body = gm_val_obj(&a);
    gm_obj_set(&a, body, "model", gm_val_str(&a, model && *model ? model : "gpt-5"));
    gm_obj_set(&a, body, "stream", gm_val_true(&a, 1));

    GMPVal *messages = gm_val_arr(&a);
    GMPVal *sys = gm_val_obj(&a);
    gm_obj_set(&a, sys, "role", gm_val_str(&a, "system"));
    gm_obj_set(&a, sys, "content", gm_val_str(&a,
        "你是一个子代理，只负责完成分配给你的调研/检索任务。"
        "不要修改任何文件，只做只读探索，输出简洁结论。"));
    gm_arr_push(&a, messages, sys);
    GMPVal *u = gm_val_obj(&a);
    gm_obj_set(&a, u, "role", gm_val_str(&a, "user"));
    gm_obj_set(&a, u, "content", gm_val_str(&a, task));
    gm_arr_push(&a, messages, u);
    gm_obj_set(&a, body, "messages", messages);

    GMBuf bj;
    gm_buf_init(&bj, &a, 4096);
    gm_write_val(&bj, body);

    GMBuf acc;
    gm_buf_init(&acc, &a, 4096);

    GMProvider pv;
    memset(&pv, 0, sizeof(pv));
    snprintf(pv.base_url, sizeof(pv.base_url), "%s", base_url ? base_url : "");
    snprintf(pv.api_key, sizeof(pv.api_key), "%s", api_key ? api_key : "");
    snprintf(pv.model, sizeof(pv.model), "%s", model && *model ? model : "gpt-5");

    char finish[64] = {0};
    double tin = 0, tout = 0;
    char *perr = NULL;
    int rc = gm_provider_chat(&pv, bj.p, sg_delta, &acc, NULL, NULL,
                              finish, sizeof(finish), &tin, &tout, &perr);

    gm_logf("子代理完成 rc=%d 输出=%zu 字", rc, acc.len);
    if (rc != 0) {
        if (err) *err = perr ? perr : strdup("子代理请求失败");
        else free(perr);
        gm_arena_free(&a);
        return -1;
    }
    free(perr);
    if (out) {
        char *r = malloc(acc.len + 1);
        if (r) { memcpy(r, acc.p ? acc.p : "", acc.len); r[acc.len] = 0; }
        *out = r;
    }
    gm_arena_free(&a);
    return 0;
}
