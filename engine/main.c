/* GM Agent · 引擎主程序
 * 用法：gm-engine --mode app-server [--base-url URL] [--model NAME]
 * 协议：JSON-RPC 2.0 over stdio，一行一条
 *
 * 内存：每轮一个 arena，整块 reset，无 free 路径（工具输出除外）。
 * 事件推送需要跨 arena 的出口，因此 emit 前用 g_out 这一小块独立 arena。
 */
#include "gm_engine.h"
#include "runtime.h"
#include <time.h>
#include <unistd.h>
#include <pthread.h>

int gm_turn_run(GMArena *arena, const GMProvider *prov, GMSession *session,
                const char *user_text, const char *system_prompt);

#define LINE_MAX_LEN 524288
#define ARENA_SIZE (16 * 1024 * 1024)
#define OUT_ARENA_SIZE (8 * 1024 * 1024)

static char g_line[LINE_MAX_LEN];
static GMArena g_out;          /* 事件输出用（index 1），跨 turn 生命周期 */
static GMArena g_turn;         /* 回合主 arena */
static GMProvider g_prov;
static pthread_mutex_t g_emitLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_t g_turnThread;
static volatile int g_turnRunning = 0;
static volatile int g_cancelFlag = 0;
static GMSession *g_session;
static int g_turn_counter = 0;

static void out_write(GMPVal *msg) {
    GMBuf b;
    gm_buf_init(&b, &g_out, 4096);
    gm_write_val(&b, msg);
    gm_buf_puts(&b, "\n");
    fwrite(b.p, 1, b.len, stdout);
    fflush(stdout);
}

/* 供 turn.c 调用：切换到输出 arena 后写入。
 * turn.c 传入的事件对象在 g_out 里构造，需在主循环 reset 前发完，
 * 所以这里把序列化结果立刻刷到 stdout，然后 reset g_out。 */
void gm_emit(GMArena *arena, GMPVal *msg) {
    (void)arena;
    pthread_mutex_lock(&g_emitLock);
    out_write(msg);
    pthread_mutex_unlock(&g_emitLock);
}

int gm_turn_cancelled(void) { return g_cancelFlag; }

typedef struct {
    GMArena arena;
    GMProvider prov;
    char *text;
    char *sys;
    GMSession *session;
} GMTurnJob;

static void *turn_thread(void *arg) {
    GMTurnJob *j = (GMTurnJob *)arg;
    int rc = gm_turn_run(&j->arena, &j->prov, j->session, j->text, j->sys);
    if (rc != 0 && !g_cancelFlag) {
        GMPVal *r = gm_val_obj(&g_out);
        GMPVal *p2 = gm_val_obj(&g_out);
        gm_obj_set(&g_out, p2, "message", gm_val_str(&g_out, "回合失败"));
        gm_obj_set(&g_out, r, "method", gm_val_str(&g_out, "gm/event/error"));
        gm_obj_set(&g_out, r, "params", p2);
        pthread_mutex_lock(&g_emitLock);
        out_write(r);
        pthread_mutex_unlock(&g_emitLock);
    }
    gm_arena_free(&j->arena);
    free(j->text);
    free(j->sys);
    free(j);
    g_turnRunning = 0;
    return NULL;
}

static int read_line(FILE *in) {
    size_t n = 0;
    int c;
    while ((c = fgetc(in)) != EOF) {
        if (c == '\n') break;
        if (n + 1 < LINE_MAX_LEN) g_line[n++] = (char)c;
    }
    if (c == EOF && n == 0) return -1;
    g_line[n] = 0;
    if (n && g_line[n - 1] == '\r') g_line[--n] = 0;
    return (int)n;
}

static void reply(GMArena *a, const GMPVal *id, GMPVal *result, const char *err_msg) {
    GMPVal *m = gm_val_obj(a);
    gm_obj_set(a, m, "jsonrpc", gm_val_str(a, "2.0"));
    gm_obj_set(a, m, "id", id ? (GMPVal *)id : gm_val_null(a));
    if (err_msg) {
        GMPVal *e = gm_val_obj(a);
        gm_obj_set(a, e, "code", gm_val_num(a, -32000));
        gm_obj_set(a, e, "message", gm_val_str(a, err_msg));
        gm_obj_set(a, m, "error", e);
    } else {
        gm_obj_set(a, m, "result", result ? result : gm_val_obj(a));
    }
    out_write(m);
    gm_arena_reset(&g_out);
}

static void load_config(void) {
    const char *base = getenv("GM_BASE_URL");
    snprintf(g_prov.base_url, sizeof(g_prov.base_url), "%s",
             base && *base ? base : "https://api.openai.com/v1/chat/completions");
    snprintf(g_prov.api_key, sizeof(g_prov.api_key), "%s", getenv("GM_API_KEY") ?: "");
    snprintf(g_prov.model, sizeof(g_prov.model), "%s", getenv("GM_MODEL") ?: "gpt-5.2");
}

/* 供 dylib 方式调用：App 在后台线程直接调这个函数，stdin/stdout 由 socketpair 重定向 */
int gm_engine_main(int argc, char **argv);

int main(int argc, char **argv) {
    return gm_engine_main(argc, argv);
}

int gm_engine_main(int argc, char **argv) {
    (void)argc;
    (void)argv;
    setvbuf(stdout, NULL, _IOLBF, 0);
    fprintf(stderr, "[gm-engine] %s starting\n", GM_VERSION);

    gm_arena_init(&g_out, OUT_ARENA_SIZE);
    gm_arena_init(&g_turn, ARENA_SIZE);
    if (!g_out.p || !g_turn.p) {
        fprintf(stderr, "[gm-engine] arena alloc failed\n");
        return 1;
    }
    load_config();

    while (1) {
        int n = read_line(stdin);
        if (n < 0) break;
        if (n == 0) continue;

        gm_arena_reset(&g_turn);
        GMPVal *msg = gm_parse(&g_turn, g_line, (size_t)n);
        if (!msg || msg->t != GM_OBJ) continue;

        const char *method = gm_str(gm_obj_get(msg, "method"));
        GMPVal *id = gm_obj_get(msg, "id");
        GMPVal *params = gm_obj_get(msg, "params");

        if (method && strcmp(method, "gm/initialize") == 0) {
            GMPVal *r = gm_val_obj(&g_turn);
            gm_obj_set(&g_turn, r, "version", gm_val_str(&g_turn, GM_VERSION));
            gm_obj_set(&g_turn, r, "protocol", gm_val_str(&g_turn, "gm-1"));
            gm_obj_set(&g_turn, r, "model", gm_val_str(&g_turn, g_prov.model));
            gm_obj_set(&g_turn, r, "configured", gm_val_true(&g_turn, g_prov.api_key[0] != 0));
            reply(&g_turn, id, r, NULL);
        } else if (method && strcmp(method, "gm/thread/start") == 0) {
            const char *want = gm_str(gm_obj_get(params, "threadId"));
            char tid[64];
            if (want && *want) {
                snprintf(tid, sizeof(tid), "%.40s", want);   /* 客户端指定：一律用它（恢复或新建） */
            } else {
                snprintf(tid, sizeof(tid), "gm-%lld-%d", (long long)time(NULL), ++g_turn_counter);
            }
            g_session = gm_session_new(tid);
            GMPVal *r = gm_val_obj(&g_turn);
            GMPVal *t = gm_val_obj(&g_turn);
            gm_obj_set(&g_turn, t, "id", gm_val_str(&g_turn, tid));
            gm_obj_set(&g_turn, r, "thread", t);
            reply(&g_turn, id, r, NULL);
        } else if (method && strcmp(method, "gm/thread/history") == 0) {
            const char *tid = gm_str(gm_obj_get(params, "threadId"));
            GMPVal *r = gm_val_obj(&g_turn);
            GMPVal *hist = gm_session_load_history(tid, &g_turn);
            gm_obj_set(&g_turn, r, "messages", hist);
            gm_obj_set(&g_turn, r, "count", gm_val_num(&g_turn, (double)gm_arr_count(hist)));
            fprintf(stderr, "[gm] history %s -> %zu 条\n", tid ? tid : "(null)", gm_arr_count(hist));
            reply(&g_turn, id, r, NULL);
        } else if (method && strcmp(method, "gm/ping") == 0) {
            reply(&g_turn, id, gm_val_str(&g_turn, "pong"), NULL);
        } else if (method && strcmp(method, "gm/runtime/install") == 0) {
            const char *url = gm_str(gm_obj_get(params, "url"));
            const char *sha = gm_str(gm_obj_get(params, "sha256"));
            const char *name = gm_str(gm_obj_get(params, "name"));
            const char *root = getenv("GM_RUNTIME_DIR");
            char dest[1024];
            if (!root || !*root) root = "/tmp/gm-runtimes";
            snprintf(dest, sizeof(dest), "%s/%s", root, name ? name : "runtime");

            /* 先回执，再阻塞安装（进度用事件推送） */
            reply(&g_turn, id, gm_val_true(&g_turn, 1), NULL);

            GMPVal *ev = gm_val_obj(&g_out);
            GMPVal *pp = gm_val_obj(&g_out);
            gm_obj_set(&g_out, pp, "name", gm_val_str(&g_out, name ? name : ""));
            gm_obj_set(&g_out, pp, "phase", gm_val_str(&g_out, "start"));
            gm_obj_set(&g_out, pp, "dest", gm_val_str(&g_out, dest));
            gm_obj_set(&g_out, ev, "method", gm_val_str(&g_out, "gm/event/runtime"));
            gm_obj_set(&g_out, ev, "params", pp);
            out_write(ev);
            gm_arena_reset(&g_out);

            char *err = NULL;
            int rc = gm_runtime_install(url, sha, dest, NULL, NULL, &err);
            GMPVal *res = gm_val_obj(&g_out);
            GMPVal *rp = gm_val_obj(&g_out);
            gm_obj_set(&g_out, rp, "name", gm_val_str(&g_out, name ? name : ""));
            gm_obj_set(&g_out, rp, "phase", gm_val_str(&g_out, rc == 0 ? "done" : "error"));
            gm_obj_set(&g_out, rp, "dest", gm_val_str(&g_out, dest));
            if (err) gm_obj_set(&g_out, rp, "message", gm_val_str(&g_out, err));
            gm_obj_set(&g_out, res, "method", gm_val_str(&g_out, "gm/event/runtime"));
            gm_obj_set(&g_out, res, "params", rp);
            out_write(res);
            gm_arena_reset(&g_out);
            free(err);
        } else if (method && strcmp(method, "gm/tools/list") == 0) {
            reply(&g_turn, id, gm_tool_specs(&g_turn), NULL);
        } else if (method && strcmp(method, "gm/config") == 0) {
            const char *base = gm_str(gm_obj_get(params, "baseURL"));
            const char *key = gm_str(gm_obj_get(params, "apiKey"));
            const char *model = gm_str(gm_obj_get(params, "model"));
            if (base && *base) {
                snprintf(g_prov.base_url, sizeof(g_prov.base_url), "%s", base);
                fprintf(stderr, "[gm] config base=%s\n", g_prov.base_url);
            }
            if (key) snprintf(g_prov.api_key, sizeof(g_prov.api_key), "%s", key);
            if (model) snprintf(g_prov.model, sizeof(g_prov.model), "%s", model);
            reply(&g_turn, id, gm_val_true(&g_turn, 1), NULL);
        } else if (method && strcmp(method, "gm/turn/start") == 0) {
            const char *text = gm_str(gm_obj_get(params, "text"));
            const char *tm = gm_str(gm_obj_get(params, "model"));
            const char *tk = gm_str(gm_obj_get(params, "apiKey"));
            const char *tb = gm_str(gm_obj_get(params, "baseURL"));
            if (tb && *tb) snprintf(g_prov.base_url, sizeof(g_prov.base_url), "%s", tb);
            if (tk && *tk) snprintf(g_prov.api_key, sizeof(g_prov.api_key), "%s", tk);
            if (tm && *tm) snprintf(g_prov.model, sizeof(g_prov.model), "%s", tm);
            fprintf(stderr, "[gm] turn model=%s key=%s base=%s\n",
                    g_prov.model, g_prov.api_key[0] ? "(set)" : "(empty)", g_prov.base_url);

            if (g_turnRunning) {
                reply(&g_turn, id, NULL, "上一轮尚未结束");
                continue;
            }
            if (!g_session) {
                char tid[64];
                snprintf(tid, sizeof(tid), "gm-%lld-%d", (long long)time(NULL), ++g_turn_counter);
                g_session = gm_session_new(tid);
            }

            GMTurnJob *job = calloc(1, sizeof(GMTurnJob));
            if (!job) { reply(&g_turn, id, NULL, "内存不足"); continue; }
            gm_arena_init(&job->arena, ARENA_SIZE);
            job->prov = g_prov;
            job->text = strdup(text ? text : "");
            {
                const char *extra = gm_str(gm_obj_get(params, "instruction"));
                char sysbuf[8192];
                snprintf(sysbuf, sizeof(sysbuf),
                    "你是 GM Agent，运行在用户 iOS 设备上。"
                    "可以使用 shell 工具读写文件、执行命令、打开应用。"
                    "回答简洁、直接给出结果与命令。%s%s",
                    (extra && *extra) ? "\n\n【用户全局指令】\n" : "",
                    (extra && *extra) ? extra : "");
                job->sys = strdup(sysbuf);
            }
            job->session = g_session;

            g_cancelFlag = 0;
            g_turnRunning = 1;
            gm_session_append_user(g_session, text ? text : "");
            if (pthread_create(&g_turnThread, NULL, turn_thread, job) != 0) {
                g_turnRunning = 0;
                gm_arena_free(&job->arena);
                free(job->text); free(job->sys); free(job);
                reply(&g_turn, id, NULL, "无法创建线程");
                continue;
            }
            pthread_detach(g_turnThread);
            reply(&g_turn, id, gm_val_true(&g_turn, 1), NULL);
        } else if (method && strcmp(method, "gm/turn/cancel") == 0) {
            g_cancelFlag = 1;
            reply(&g_turn, id, gm_val_true(&g_turn, 1), NULL);
        } else if (method && strcmp(method, "gm/tool/shell") == 0) {
            const char *cmd = gm_str(gm_obj_get(params, "command"));
            int code = 0;
            char *out = gm_tool_run_shell(cmd, NULL, 60000, &code);
            GMPVal *r = gm_val_obj(&g_turn);
            gm_obj_set(&g_turn, r, "output", gm_val_str(&g_turn, out ? out : ""));
            gm_obj_set(&g_turn, r, "code", gm_val_num(&g_turn, code));
            free(out);
            reply(&g_turn, id, r, NULL);
        } else if (method) {
            reply(&g_turn, id, NULL, "method not found");
        }
    }
    gm_arena_free(&g_out);
    gm_arena_free(&g_turn);
    return 0;
}
