/* GM Agent · 引擎主程序
 * 用法：gm-engine --mode app-server [--base-url URL] [--model NAME]
 * 协议：JSON-RPC 2.0 over stdio，一行一条
 *
 * 内存：每轮一个 arena，整块 reset，无 free 路径（工具输出除外）。
 * 事件推送需要跨 arena 的出口，因此 emit 前用 g_out 这一小块独立 arena。
 */
#include "gm_engine.h"
#include "runtime.h"
#include "codex.h"
#include "theos.h"
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
static pthread_t g_turnThread;
static volatile int g_turnRunning = 0;
static volatile int g_cancelFlag = 0;
static GMSession *g_session;
static int g_turn_counter = 0;

/* 线程安全输出：每次用独立临时 arena，序列化后立刻释放。
 * （早期版本共享 g_out 且从不重置，长会话会耗尽 8MB 并静默丢输出） */
static pthread_mutex_t g_outLock = PTHREAD_MUTEX_INITIALIZER;

static void out_write(GMPVal *msg) {
    if (!msg) return;
    pthread_mutex_lock(&g_outLock);
    GMArena tmp;
    gm_arena_init(&tmp, 64 * 1024);
    if (tmp.p) {
        GMBuf b;
        gm_buf_init(&b, &tmp, 4096);
        gm_write_val(&b, msg);
        gm_buf_puts(&b, "\n");
        if (b.p && b.len) {
            fwrite(b.p, 1, b.len, stdout);
            fflush(stdout);
        }
        gm_arena_free(&tmp);
    }
    pthread_mutex_unlock(&g_outLock);
}

/* 供 turn.c 调用：切换到输出 arena 后写入。
 * turn.c 传入的事件对象在 g_out 里构造，需在主循环 reset 前发完，
 * 所以这里把序列化结果立刻刷到 stdout，然后 reset g_out。 */
void gm_emit(GMArena *arena, GMPVal *msg) {
    (void)arena;
    out_write(msg);   /* out_write 内部已加锁 */
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
        GMArena tmp;
        gm_arena_init(&tmp, 64 * 1024);
        if (tmp.p) {
            GMPVal *r = gm_val_obj(&tmp);
            GMPVal *p2 = gm_val_obj(&tmp);
            gm_obj_set(&tmp, p2, "message", gm_val_str(&tmp, "回合失败"));
            gm_obj_set(&tmp, r, "method", gm_val_str(&tmp, "gm/event/error"));
            gm_obj_set(&tmp, r, "params", p2);
            out_write(r);
            gm_arena_free(&tmp);
        }
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
    gm_log_init();
    gm_logf("engine %s starting, HOME=%s", GM_VERSION, getenv("HOME") ?: "(null)");

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
            gm_logf("history %s -> %zu 条", tid ? tid : "(null)", gm_arr_count(hist));
            reply(&g_turn, id, r, NULL);
        } else if (method && strcmp(method, "gm/ping") == 0) {
            reply(&g_turn, id, gm_val_str(&g_turn, "pong"), NULL);
        } else if (method && strcmp(method, "gm/runtime/install") == 0) {
            const char *url = gm_str(gm_obj_get(params, "url"));
            const char *sha = gm_str(gm_obj_get(params, "sha256"));
            GMPVal *sv = gm_obj_get(params, "expectSize");
            GMPVal *skip = gm_obj_get(params, "skipVerify");
            const char *name = gm_str(gm_obj_get(params, "name"));
            const char *root = getenv("GM_RUNTIME_DIR");
            char dest[1024];
            if (!root || !*root) root = "/tmp/gm-runtimes";
            snprintf(dest, sizeof(dest), "%s/%s", root, name ? name : "runtime");

            /* 先回执，再阻塞安装（进度用事件推送） */
            reply(&g_turn, id, gm_val_true(&g_turn, 1), NULL);

            GMArena ra;
            gm_arena_init(&ra, 64 * 1024);
            GMPVal *ev = gm_val_obj(&ra);
            GMPVal *pp = gm_val_obj(&ra);
            gm_obj_set(&ra, pp, "name", gm_val_str(&ra, name ? name : ""));
            gm_obj_set(&ra, pp, "phase", gm_val_str(&ra, "start"));
            gm_obj_set(&ra, pp, "dest", gm_val_str(&ra, dest));
            gm_obj_set(&ra, ev, "method", gm_val_str(&ra, "gm/event/runtime"));
            gm_obj_set(&ra, ev, "params", pp);
            out_write(ev);
            gm_arena_free(&ra);

            char *err = NULL;
            int rc = gm_runtime_install(url, sha, dest, NULL, NULL, &err);
            GMArena rb;
            gm_arena_init(&rb, 64 * 1024);
            GMPVal *res = gm_val_obj(&rb);
            GMPVal *rp = gm_val_obj(&rb);
            gm_obj_set(&rb, rp, "name", gm_val_str(&rb, name ? name : ""));
            gm_obj_set(&rb, rp, "phase", gm_val_str(&rb, rc == 0 ? "done" : "error"));
            gm_obj_set(&rb, rp, "dest", gm_val_str(&rb, dest));
            if (err) gm_obj_set(&rb, rp, "message", gm_val_str(&rb, err));
            gm_obj_set(&rb, res, "method", gm_val_str(&rb, "gm/event/runtime"));
            gm_obj_set(&rb, res, "params", rp);
            out_write(res);
            gm_arena_free(&rb);
            free(err);
        } else if (method && strcmp(method, "gm/subagent/run") == 0) {
            const char *task = gm_str(gm_obj_get(params, "task"));
            const char *m2 = gm_str(gm_obj_get(params, "model"));
            reply(&g_turn, id, gm_val_true(&g_turn, 1), NULL);

            /* 通知 UI：子代理开始 */
            GMArena na;
            gm_arena_init(&na, 16384);
            GMPVal *n = gm_val_obj(&na);
            GMPVal *pp = gm_val_obj(&na);
            gm_obj_set(&na, pp, "phase", gm_val_str(&na, "start"));
            gm_obj_set(&na, pp, "task", gm_val_str(&na, task ? task : ""));
            gm_obj_set(&na, n, "method", gm_val_str(&na, "gm/event/subagent"));
            gm_obj_set(&na, n, "params", pp);
            out_write(n);
            gm_arena_free(&na);

            char *sout = NULL, *serr = NULL;
            const char *useModel = (m2 && *m2) ? m2 : g_prov.model;
            int src = gm_subagent_run(task, useModel, g_prov.base_url, g_prov.api_key, &sout, &serr);

            GMArena rb;
            gm_arena_init(&rb, 65536);
            GMPVal *r2 = gm_val_obj(&rb);
            GMPVal *rp = gm_val_obj(&rb);
            gm_obj_set(&rb, rp, "phase", gm_val_str(&rb, src == 0 ? "done" : "error"));
            gm_obj_set(&rb, rp, "task", gm_val_str(&rb, task ? task : ""));
            if (src == 0) gm_obj_set(&rb, rp, "output", gm_val_str(&rb, sout ? sout : ""));
            else gm_obj_set(&rb, rp, "message", gm_val_str(&rb, serr ? serr : "失败"));
            gm_obj_set(&rb, r2, "method", gm_val_str(&rb, "gm/event/subagent"));
            gm_obj_set(&rb, r2, "params", rp);
            out_write(r2);
            gm_arena_free(&rb);
            free(sout); free(serr);
        } else if (method && strcmp(method, "gm/theos/status") == 0) {
            GMPVal *r = gm_val_obj(&g_turn);
            gm_obj_set(&g_turn, r, "available", gm_val_true(&g_turn, gm_theos_available()));
            char *root = gm_theos_root();
            gm_obj_set(&g_turn, r, "root", gm_val_str(&g_turn, root ? root : ""));
            if (root) free(root);
            reply(&g_turn, id, r, NULL);
        } else if (method && strcmp(method, "gm/theos/build") == 0) {
            const char *path = gm_str(gm_obj_get(params, "path"));
            const char *target = gm_str(gm_obj_get(params, "target"));
            const char *arch = gm_str(gm_obj_get(params, "arch"));
            const char *flags = gm_str(gm_obj_get(params, "flags"));
            char *out = NULL, *err = NULL; int code = 0;
            int rc = gm_theos_build(path, target, arch, flags, NULL, NULL, &out, &code, &err);
            GMPVal *r = gm_val_obj(&g_turn);
            gm_obj_set(&g_turn, r, "code", gm_val_num(&g_turn, code));
            gm_obj_set(&g_turn, r, "output", gm_val_str(&g_turn, out ? out : ""));
            if (err) gm_obj_set(&g_turn, r, "error", gm_val_str(&g_turn, err));
            reply(&g_turn, id, r, rc == 0 ? NULL : (err ? err : "编译失败"));
            free(out); free(err);
        } else if (method && strcmp(method, "gm/theos/clean") == 0) {
            const char *path = gm_str(gm_obj_get(params, "path"));
            char *out = NULL, *err = NULL; int code = 0;
            gm_theos_clean(path, &out, &code, &err);
            GMPVal *r = gm_val_obj(&g_turn);
            gm_obj_set(&g_turn, r, "code", gm_val_num(&g_turn, code));
            gm_obj_set(&g_turn, r, "output", gm_val_str(&g_turn, out ? out : ""));
            reply(&g_turn, id, r, NULL);
            free(out); free(err);
        } else if (method && strcmp(method, "gm/codex/status") == 0) {
            GMPVal *r = gm_val_obj(&g_turn);
            gm_obj_set(&g_turn, r, "available", gm_val_true(&g_turn, gm_codex_available()));
            gm_obj_set(&g_turn, r, "ready", gm_val_true(&g_turn, gm_codex_ready()));
            char *bin = gm_codex_find_binary();
            gm_obj_set(&g_turn, r, "binary", gm_val_str(&g_turn, bin ? bin : ""));
            if (bin) free(bin);
            reply(&g_turn, id, r, NULL);
        } else if (method && strcmp(method, "gm/codex/start") == 0) {
            char *e = NULL;
            int rc = gm_codex_start(&e);
            if (rc == 0) {
                reply(&g_turn, id, gm_val_true(&g_turn, 1), NULL);
            } else {
                reply(&g_turn, id, NULL, e ? e : "启动失败");
                free(e);
            }
        } else if (method && strcmp(method, "gm/codex/stop") == 0) {
            gm_codex_stop();
            reply(&g_turn, id, gm_val_true(&g_turn, 1), NULL);
        } else if (method && strcmp(method, "gm/tools/list") == 0) {
            reply(&g_turn, id, gm_tool_specs(&g_turn), NULL);
        } else if (method && strcmp(method, "gm/config") == 0) {
            const char *base = gm_str(gm_obj_get(params, "baseURL"));
            const char *key = gm_str(gm_obj_get(params, "apiKey"));
            const char *model = gm_str(gm_obj_get(params, "model"));
            if (base && *base) {
                snprintf(g_prov.base_url, sizeof(g_prov.base_url), "%s", base);
                gm_logf("config base=%s key=%s model=%s", g_prov.base_url, g_prov.api_key[0] ? "(set)" : "(empty)", g_prov.model);
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
            gm_logf("turn start model=%s key=%s base=%s",
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

            const char *eng = gm_str(gm_obj_get(params, "engine"));
            /* auto：按供应商能力自动选择（对齐 MT 的 CAModelCapabilityClassifier） */
            if (eng && strcmp(eng, "auto") == 0) {
                int wantCodex = 0;
                if (strstr(g_prov.base_url, "api.openai.com")) wantCodex = 1;
                if (strstr(g_prov.base_url, "/responses")) wantCodex = 1;
                if (strncmp(g_prov.model, "gpt-5", 5) == 0) wantCodex = 1;
                if (strncmp(g_prov.model, "gpt-6", 5) == 0) wantCodex = 1;
                if (wantCodex && gm_codex_available()) {
                    eng = "codex";
                    gm_logf("auto → codex (model=%s)", g_prov.model);
                } else {
                    eng = "api";
                    gm_logf("auto → api (model=%s, codex=%d)", g_prov.model, gm_codex_available());
                }
            }
            if (eng && strcmp(eng, "codex") == 0) {
                /* 走 Codex 运行时 */
                if (!gm_codex_ready()) {
                    char *ce = NULL;
                    if (gm_codex_start(&ce) != 0) {
                        reply(&g_turn, id, NULL, ce ? ce : "codex 启动失败");
                        free(ce);
                        continue;
                    }
                }
                /* 用当前配置刷新 codex 的 config.toml */
                gm_codex_write_config(g_prov.base_url, g_prov.api_key, g_prov.model, NULL);
                setenv("GM_CODEX_API_KEY", g_prov.api_key, 1);

                reply(&g_turn, id, gm_val_true(&g_turn, 1), NULL);
                gm_session_append_user(g_session, text ? text : "");

                g_turnRunning = 1;
                char *ce = NULL;
                gm_codex_turn(g_session ? gm_session_id(g_session) : "", text ? text : "", &ce);
                if (ce) {
                    GMArena ea;
                    gm_arena_init(&ea, 16384);
                    GMPVal *r = gm_val_obj(&ea);
                    GMPVal *p2 = gm_val_obj(&ea);
                    gm_obj_set(&ea, p2, "message", gm_val_str(&ea, ce));
                    gm_obj_set(&ea, r, "method", gm_val_str(&ea, "gm/event/error"));
                    gm_obj_set(&ea, r, "params", p2);
                    out_write(r);
                    gm_arena_free(&ea);
                    free(ce);
                }
                g_turnRunning = 0;
                continue;
            }

            const char *cwd = gm_str(gm_obj_get(params, "cwd"));
            if (cwd && *cwd) setenv("GM_CWD", cwd, 1);

            GMTurnJob *job = calloc(1, sizeof(GMTurnJob));
            if (!job) { reply(&g_turn, id, NULL, "内存不足"); continue; }
            gm_arena_init(&job->arena, ARENA_SIZE);
            job->prov = g_prov;
            job->text = strdup(text ? text : "");
            {
                const char *extra = gm_str(gm_obj_get(params, "instruction"));
                const char *skills = gm_str(gm_obj_get(params, "skills"));
                char sysbuf[16384];
                snprintf(sysbuf, sizeof(sysbuf),
                    "你是 GM Agent，运行在用户 iOS 设备上。"
                    "可以使用 shell 工具读写文件、执行命令、打开应用。"
                    "回答简洁、直接给出结果与命令。%s%s",
                    (extra && *extra) ? "\n\n【用户全局指令】\n" : "",
                    (extra && *extra) ? extra : "");
                if (skills && *skills) {
                    size_t used = strlen(sysbuf);
                    snprintf(sysbuf + used, sizeof(sysbuf) - used,
                             "\n\n【可用 Skills】\n%s", skills);
                }
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
