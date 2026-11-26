/* GM Agent · 引擎公共头（C99，零依赖，可单测）
 *
 * 内存策略：所有 JSON 对象/字符串/序列化缓冲都来自 GMArena（bump allocator），
 * 生命周期按「一轮请求」整体 reset，从根上杜绝 double-free / 悬垂指针。
 * （iSH 环境下 glibc double-free 会直接 SIGSEGV，且无诊断输出。）
 */
#ifndef GM_ENGINE_H
#define GM_ENGINE_H

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdarg.h>

#define GM_VERSION "0.1.0"

/* ---------------- 区域分配器 ---------------- */
typedef struct GMArena {
    char *p;
    size_t len;
    size_t cap;
} GMArena;

void gm_arena_init(GMArena *a, size_t cap);
void gm_arena_reset(GMArena *a);
void gm_arena_free(GMArena *a);

/* ---------------- 输出缓冲 ---------------- */
typedef struct GMBuf {
    char *p;
    size_t len;
    size_t cap;
    GMArena *arena;
} GMBuf;

void gm_buf_init(GMBuf *b, GMArena *arena, size_t cap);
void gm_buf_append(GMBuf *b, const char *data, size_t n);
void gm_buf_puts(GMBuf *b, const char *s);
void gm_buf_printf(GMBuf *b, const char *fmt, ...);

/* ---------------- 值模型 ---------------- */
typedef enum { GM_NULL, GM_BOOL, GM_NUM, GM_STR, GM_ARR, GM_OBJ } GMPType;

typedef struct GMPVal GMPVal;
struct GMPVal {
    GMPType t;
    union {
        int b;
        double n;
        struct { char *p; } s;
        struct { GMPVal **items; size_t count; } a;
        struct { char **keys; GMPVal **vals; size_t count; } o;
    } u;
};

/* 构造（arena 分配） */
GMPVal *gm_val_null(GMArena *a);
GMPVal *gm_val_true(GMArena *a, int b);
GMPVal *gm_val_num(GMArena *a, double d);
GMPVal *gm_val_str(GMArena *a, const char *s);
GMPVal *gm_val_strn(GMArena *a, const char *s, size_t n);
GMPVal *gm_val_obj(GMArena *a);
GMPVal *gm_val_arr(GMArena *a);

void gm_obj_set(GMArena *a, GMPVal *obj, const char *key, GMPVal *val);
void gm_arr_push(GMArena *a, GMPVal *arr, GMPVal *val);

GMPVal *gm_obj_get(const GMPVal *obj, const char *key);
const char *gm_str(const GMPVal *v);
double gm_num(const GMPVal *v, double dflt);
int gm_bool(const GMPVal *v, int dflt);
size_t gm_arr_count(const GMPVal *v);
GMPVal *gm_arr_at(const GMPVal *v, size_t i);

/* 解析 / 序列化 */
GMPVal *gm_parse(GMArena *a, const char *json, size_t len);
void gm_write_val(GMBuf *b, const GMPVal *v);

/* ---------------- 会话 ---------------- */
typedef struct GMSession GMSession;
GMSession *gm_session_new(const char *thread_id);
void gm_session_free(GMSession *s);
const char *gm_session_id(const GMSession *s);
void gm_session_append(GMSession *s, const char *role, const char *text);
void gm_session_append_user(GMSession *s, const char *text);
void gm_session_append_assistant(GMSession *s, const char *text);

/* ---------------- 提供方 ---------------- */
typedef void (*GMDeltaFn)(void *ctx, const char *kind, const char *delta);
typedef void (*GMToolCallFn)(void *ctx, const char *id, const char *name, const char *args_json);

typedef struct GMProvider {
    char base_url[512];
    char api_key[1024];
    char model[128];
} GMProvider;

/* 一次流式请求；返回 0 成功 */
int gm_provider_chat(const GMProvider *p, const char *body_json,
                     GMDeltaFn on_delta, void *dctx,
                     GMToolCallFn on_tool, void *tctx,
                     char *finish_reason_out, size_t fro_cap,
                     double *in_tokens, double *out_tokens,
                     char **err_out);

/* ---------------- 宿主工具（由 App 实现，引擎在同进程调用） ---------------- */
typedef int (*GMHostToolFn)(const char *name, const char *args_json, char **out);
void gm_set_host_tool_handler(GMHostToolFn fn);
GMHostToolFn gm_host_tool_handler(void);

/* ---------------- 工具 ---------------- */
char *gm_tool_run_shell(const char *command, const char *cwd, int timeout_ms, int *code);
GMPVal *gm_tool_specs(GMArena *a);

#endif
