/* GM Agent · Codex 运行时集成实现 */
#include "codex.h"

/* 由 main.c 提供 */
extern void gm_emit(GMArena *arena, GMPVal *msg);
#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <signal.h>
#include <pthread.h>
#include <dirent.h>
#include <errno.h>
#include <time.h>

static pid_t g_codexPid = -1;
static int g_toCodex = -1;      /* 我们写 */
static int g_fromCodex = -1;    /* 我们读 */
static pthread_t g_reader;
static volatile int g_ready = 0;
static volatile int g_turnDone = 0;
static volatile int g_turnInterrupted = 0;
static long long g_nextId = 1;
static char g_threadId[128];
static pthread_mutex_t g_writeLock = PTHREAD_MUTEX_INITIALIZER;
static char g_pendingErr[512];

/* ---------- 查找二进制 ---------- */

static int is_exec_file(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0) return 0;
    if (!S_ISREG(st.st_mode)) return 0;
    if (!(st.st_mode & S_IXUSR)) return 0;
    /* 检查 Mach-O 魔数 */
    FILE *f = fopen(path, "rb");
    if (!f) return 0;
    unsigned char m[4] = {0};
    size_t n = fread(m, 1, 4, f);
    fclose(f);
    if (n < 4) return 0;
    if (m[0] != 0xCF && m[0] != 0xCE && m[0] != 0xCA) return 0;
    return 1;
}

static char *search_dir(const char *dir, int depth) {
    if (depth > 6) return NULL;
    DIR *d = opendir(dir);
    if (!d) return NULL;
    struct dirent *e;
    char path[1200];
    while ((e = readdir(d)) != NULL) {
        if (e->d_name[0] == '.') continue;
        snprintf(path, sizeof(path), "%s/%s", dir, e->d_name);
        struct stat st;
        if (lstat(path, &st) != 0) continue;
        if (S_ISDIR(st.st_mode)) {
            char *r = search_dir(path, depth + 1);
            if (r) { closedir(d); return r; }
        } else if (strcmp(e->d_name, "codex") == 0 || strcmp(e->d_name, "codex.real") == 0) {
            if (is_exec_file(path)) {
                closedir(d);
                char *out = malloc(strlen(path) + 1);
                if (out) strcpy(out, path);
                return out;
            }
        }
    }
    closedir(d);
    return NULL;
}

char *gm_codex_find_binary(void) {
    const char *rt = getenv("GM_RUNTIME_DIR");
    if (rt && *rt) {
        char dir[1024];
        snprintf(dir, sizeof(dir), "%s/codex", rt);
        char *r = search_dir(dir, 0);
        if (r) return r;
        r = search_dir(rt, 0);
        if (r) return r;
    }
    const char *cands[] = {
        "/var/jb/usr/bin/codex", "/var/jb/usr/local/bin/codex",
        "/usr/bin/codex", "/usr/local/bin/codex", NULL
    };
    for (int i = 0; cands[i]; i++)
        if (is_exec_file(cands[i])) { char *o = strdup(cands[i]); return o; }
    return NULL;
}

int gm_codex_available(void) {
    char *p = gm_codex_find_binary();
    if (!p) return 0;
    free(p);
    return 1;
}

/* ---------- 配置 ---------- */

int gm_codex_write_config(const char *base_url, const char *api_key,
                          const char *model, char **err) {
    const char *home = getenv("GM_CODEX_HOME");
    if (!home || !*home) { if (err) *err = strdup("未设置 GM_CODEX_HOME"); return -1; }
    /* mkdir -p（iOS 禁用 system） */
    {
        char tmp[1024];
        snprintf(tmp, sizeof(tmp), "%s", home);
        for (char *q = tmp + 1; *q; q++) {
            if (*q == '/') { *q = 0; mkdir(tmp, 0755); *q = '/'; }
        }
        mkdir(tmp, 0755);
    }

    /* base_url 去掉 /chat/completions 后缀 */
    char base[512];
    snprintf(base, sizeof(base), "%s", base_url ? base_url : "");
    char *tail = strstr(base, "/chat/completions");
    if (tail) *tail = 0;

    char path[1200];
    snprintf(path, sizeof(path), "%s/config.toml", home);
    FILE *f = fopen(path, "w");
    if (!f) { if (err) *err = strdup("无法写入 config.toml"); return -1; }

    fprintf(f, "model = \"%s\"\n", model && *model ? model : "gpt-5");
    fprintf(f, "model_provider = \"gmcustom\"\n");
    fprintf(f, "approval_policy = \"never\"\n");
    fprintf(f, "sandbox_mode = \"danger-full-access\"\n");
    fprintf(f, "model_reasoning_effort = \"medium\"\n\n");
    fprintf(f, "[model_providers.gmcustom]\n");
    fprintf(f, "name = \"GM Custom\"\n");
    fprintf(f, "base_url = \"%s\"\n", base);
    fprintf(f, "env_key = \"GM_CODEX_API_KEY\"\n");
    fprintf(f, "wire_api = \"chat\"\n");
    fclose(f);
    gm_logf("codex config 写入 %s (base=%s model=%s)", path, base, model ? model : "?");
    return 0;
}

/* ---------- 进程通信 ---------- */

static void codex_send_raw(const char *line) {
    if (g_toCodex < 0) return;
    pthread_mutex_lock(&g_writeLock);
    size_t n = strlen(line);
    ssize_t w = write(g_toCodex, line, n);
    (void)w;
    pthread_mutex_unlock(&g_writeLock);
}

static long long codex_send(GMPVal *msg) {
    GMArena a;
    gm_arena_init(&a, 64 * 1024);
    GMBuf b;
    gm_buf_init(&b, &a, 4096);
    gm_write_val(&b, msg);
    gm_buf_puts(&b, "\n");
    if (b.p) codex_send_raw(b.p);
    gm_arena_free(&a);
    return 0;
}

/* ---------- 读线程：解析 Codex 通知 ---------- */

static void emit_delta(const char *kind, const char *text) {
    GMArena a;
    gm_arena_init(&a, 64 * 1024);
    GMPVal *n = gm_val_obj(&a);
    GMPVal *p = gm_val_obj(&a);
    gm_obj_set(&a, p, "kind", gm_val_str(&a, kind));
    gm_obj_set(&a, p, "delta", gm_val_str(&a, text));
    gm_obj_set(&a, n, "method", gm_val_str(&a, "gm/event/delta"));
    gm_obj_set(&a, n, "params", p);
    gm_emit(&a, n);
    gm_arena_free(&a);
}

static void emit_turn_end(const char *finish, double tin, double tout) {
    GMArena a;
    gm_arena_init(&a, 64 * 1024);
    GMPVal *n = gm_val_obj(&a);
    GMPVal *p = gm_val_obj(&a);
    gm_obj_set(&a, p, "finish", gm_val_str(&a, finish ? finish : "stop"));
    gm_obj_set(&a, p, "inputTokens", gm_val_num(&a, tin));
    gm_obj_set(&a, p, "outputTokens", gm_val_num(&a, tout));
    gm_obj_set(&a, n, "method", gm_val_str(&a, "gm/event/turnEnd"));
    gm_obj_set(&a, n, "params", p);
    gm_emit(&a, n);
    gm_arena_free(&a);
}

static void handle_codex_msg(GMPVal *msg) {
    if (!msg || msg->t != GM_OBJ) return;
    const char *method = gm_str(gm_obj_get(msg, "method"));
    if (!method) return;
    GMPVal *params = gm_obj_get(msg, "params");

    if (strcmp(method, "item/agentMessage/delta") == 0) {
        const char *d = gm_str(gm_obj_get(params, "delta"));
        if (d && *d) emit_delta("text", d);
        return;
    }
    if (strcmp(method, "item/reasoning/summaryTextDelta") == 0 ||
        strcmp(method, "item/reasoning/textDelta") == 0) {
        const char *d = gm_str(gm_obj_get(params, "delta"));
        if (d && *d) emit_delta("reasoning", d);
        return;
    }
    if (strcmp(method, "item/commandExecution/outputDelta") == 0) {
        const char *d = gm_str(gm_obj_get(params, "delta"));
        if (d && *d) emit_delta("tool", d);
        return;
    }
    if (strcmp(method, "item/commandExecution/requestApproval") == 0) {
        /* 自动批准（danger-full-access 下通常不会来） */
        const char *id = gm_str(gm_obj_get(msg, "id"));
        if (id) {
            GMArena a;
            gm_arena_init(&a, 8192);
            GMPVal *r = gm_val_obj(&a);
            gm_obj_set(&a, r, "id", gm_val_str(&a, id));
            GMPVal *res = gm_val_obj(&a);
            gm_obj_set(&a, res, "decision", gm_val_str(&a, "acceptForSession"));
            gm_obj_set(&a, r, "result", res);
            codex_send(r);
            gm_arena_free(&a);
        }
        return;
    }
    if (strcmp(method, "turn/completed") == 0) {
        GMPVal *turn = gm_obj_get(params, "turn");
        const char *status = gm_str(gm_obj_get(turn, "status"));
        GMPVal *usage = gm_obj_get(params, "usage");
        if (!usage) usage = gm_obj_get(turn, "usage");
        double tin = gm_num(gm_obj_get(usage, "inputTokens"), 0);
        double tout = gm_num(gm_obj_get(usage, "outputTokens"), 0);
        emit_turn_end(status ? status : "stop", tin, tout);
        g_turnDone = 1;
        return;
    }
    if (strcmp(method, "thread/started") == 0) {
        GMPVal *th = gm_obj_get(params, "thread");
        const char *id = gm_str(gm_obj_get(th, "id"));
        if (id) snprintf(g_threadId, sizeof(g_threadId), "%s", id);
        return;
    }
    if (strcmp(method, "error") == 0) {
        const char *m = gm_str(gm_obj_get(params, "message"));
        gm_logf("codex error: %s", m ? m : "?");
        return;
    }
}

static void *codex_reader_thread(void *arg) {
    (void)arg;
    char buf[65536];
    size_t len = 0;
    char *line = malloc(131072);
    if (!line) return NULL;
    size_t lineLen = 0;

    for (;;) {
        ssize_t n = read(g_fromCodex, buf, sizeof(buf));
        if (n <= 0) break;
        for (ssize_t i = 0; i < n; i++) {
            char c = buf[i];
            if (c == '\n') {
                line[lineLen] = 0;
                if (lineLen > 2) {
                    GMArena a;
                    gm_arena_init(&a, 256 * 1024);
                    GMPVal *v = gm_parse(&a, line, lineLen);
                    if (v) {
                        /* 响应报文（有 id 无 method）：记录错误 */
                        if (!gm_str(gm_obj_get(v, "method"))) {
                            GMPVal *e = gm_obj_get(v, "error");
                            if (e) {
                                const char *m = gm_str(gm_obj_get(e, "message"));
                                if (m) snprintf(g_pendingErr, sizeof(g_pendingErr), "%s", m);
                                gm_logf("codex rpc error: %s", m ? m : "?");
                            }
                        } else {
                            handle_codex_msg(v);
                        }
                    } else {
                        gm_logf("codex 无法解析: %.120s", line);
                    }
                    gm_arena_free(&a);
                }
                lineLen = 0;
            } else if (lineLen + 1 < 131072) {
                line[lineLen++] = c;
            }
        }
        len = 0;
        (void)len;
    }
    free(line);
    gm_logf("codex 读线程结束");
    return NULL;
}

/* ---------- 启动 ---------- */

int gm_codex_start(char **err) {
    if (g_codexPid > 0) return 0;

    char *bin = gm_codex_find_binary();
    if (!bin) { if (err) *err = strdup("未找到 codex 可执行文件"); return -1; }
    gm_logf("codex 二进制: %s", bin);

    int in[2], out[2], errp[2];
    if (pipe(in) || pipe(out) || pipe(errp)) {
        free(bin);
        if (err) *err = strdup("管道创建失败");
        return -1;
    }

    pid_t pid = fork();
    if (pid < 0) {
        free(bin);
        if (err) *err = strdup("fork 失败");
        return -1;
    }
    if (pid == 0) {
        dup2(in[0], STDIN_FILENO);
        dup2(out[1], STDOUT_FILENO);
        dup2(errp[1], STDERR_FILENO);
        close(in[0]); close(in[1]);
        close(out[0]); close(out[1]);
        close(errp[0]); close(errp[1]);

        const char *home = getenv("GM_CODEX_HOME");
        if (home && *home) setenv("CODEX_HOME", home, 1);
        const char *key = getenv("GM_CODEX_API_KEY");
        if (key && *key) setenv("GM_CODEX_API_KEY", key, 1);

        /* 补 PATH，让 codex 能找到自己的 helper */
        const char *oldp = getenv("PATH");
        char np[2048];
        snprintf(np, sizeof(np), "%s/../..:%s", bin, oldp ? oldp : "/usr/bin:/bin");
        setenv("PATH", np, 1);

        char *argv[] = { bin, "app-server", "--listen", "stdio://", NULL };
        execv(bin, argv);
        /* 退路：不同版本参数不同 */
        char *argv2[] = { bin, "app-server", NULL };
        execv(bin, argv2);
        _exit(127);
    }

    close(in[0]); close(out[1]); close(errp[1]);
    g_toCodex = in[1];
    g_fromCodex = out[0];
    g_codexPid = pid;

    /* stderr 转发到我们的日志 */
    int efd = errp[0];
    fcntl(efd, F_SETFL, O_NONBLOCK);

    pthread_create(&g_reader, NULL, codex_reader_thread, NULL);
    pthread_detach(g_reader);

    /* 握手：initialize → initialized */
    {
        GMArena a;
        gm_arena_init(&a, 16384);
        GMPVal *m = gm_val_obj(&a);
        gm_obj_set(&a, m, "id", gm_val_num(&a, g_nextId++));
        gm_obj_set(&a, m, "method", gm_val_str(&a, "initialize"));
        GMPVal *p = gm_val_obj(&a);
        GMPVal *ci = gm_val_obj(&a);
        gm_obj_set(&a, ci, "name", gm_val_str(&a, "gm-agent"));
        gm_obj_set(&a, ci, "title", gm_val_str(&a, "GM Agent"));
        gm_obj_set(&a, ci, "version", gm_val_str(&a, "1.4.0"));
        gm_obj_set(&a, p, "clientInfo", ci);
        gm_obj_set(&a, m, "params", p);
        codex_send(m);
        gm_arena_free(&a);
    }
    {
        GMArena a;
        gm_arena_init(&a, 4096);
        GMPVal *m = gm_val_obj(&a);
        gm_obj_set(&a, m, "method", gm_val_str(&a, "initialized"));
        codex_send(m);
        gm_arena_free(&a);
    }

    /* 等待就绪（最多 12 秒） */
    for (int i = 0; i < 120; i++) {
        if (g_threadId[0] == 0) {
            /* 尝试开线程来验证握手成功 */
            char *tid = gm_codex_thread_start(NULL);
            if (tid) { snprintf(g_threadId, sizeof(g_threadId), "%s", tid); free(tid); break; }
        }
        usleep(100000);
    }
    if (!g_threadId[0]) {
        gm_logf("codex 握手超时");
        if (err) *err = strdup(g_pendingErr[0] ? g_pendingErr : "codex 握手超时（未响应 initialize）");
        free(bin);
        return -1;
    }
    g_ready = 1;
    gm_logf("codex 就绪 thread=%s", g_threadId);
    free(bin);
    return 0;
}

void gm_codex_stop(void) {
    if (g_toCodex >= 0) { close(g_toCodex); g_toCodex = -1; }
    if (g_fromCodex >= 0) { close(g_fromCodex); g_fromCodex = -1; }
    if (g_codexPid > 0) { kill(g_codexPid, SIGTERM); waitpid(g_codexPid, NULL, 0); g_codexPid = -1; }
    g_ready = 0;
}

int gm_codex_ready(void) { return g_ready; }

char *gm_codex_thread_start(char **err) {
    GMArena a;
    gm_arena_init(&a, 16384);
    GMPVal *m = gm_val_obj(&a);
    gm_obj_set(&a, m, "id", gm_val_num(&a, g_nextId++));
    gm_obj_set(&a, m, "method", gm_val_str(&a, "thread/start"));
    GMPVal *p = gm_val_obj(&a);
    gm_obj_set(&a, p, "cwd", gm_val_str(&a, getenv("HOME") ?: "/var/mobile"));
    gm_obj_set(&a, p, "approvalPolicy", gm_val_str(&a, "never"));
    gm_obj_set(&a, p, "sandbox", gm_val_str(&a, "danger-full-access"));
    gm_obj_set(&a, m, "params", p);
    codex_send(m);
    gm_arena_free(&a);

    /* 等 thread/started 或超时 */
    for (int i = 0; i < 60; i++) {
        if (g_threadId[0]) {
            char *o = strdup(g_threadId);
            return o;
        }
        usleep(50000);
    }
    if (err) *err = strdup(g_pendingErr[0] ? g_pendingErr : "thread/start 无响应");
    return NULL;
}

int gm_codex_turn(const char *thread_id, const char *text, char **err) {
    if (!g_ready) { if (err) *err = strdup("codex 未就绪"); return -1; }
    g_turnDone = 0;
    g_turnInterrupted = 0;
    g_pendingErr[0] = 0;

    GMArena a;
    gm_arena_init(&a, 32768);
    GMPVal *m = gm_val_obj(&a);
    gm_obj_set(&a, m, "id", gm_val_num(&a, g_nextId++));
    gm_obj_set(&a, m, "method", gm_val_str(&a, "turn/start"));
    GMPVal *p = gm_val_obj(&a);
    gm_obj_set(&a, p, "threadId", gm_val_str(&a, thread_id && *thread_id ? thread_id : g_threadId));
    GMPVal *input = gm_val_arr(&a);
    GMPVal *item = gm_val_obj(&a);
    gm_obj_set(&a, item, "type", gm_val_str(&a, "text"));
    gm_obj_set(&a, item, "text", gm_val_str(&a, text ? text : ""));
    gm_arr_push(&a, input, item);
    gm_obj_set(&a, p, "input", input);
    gm_obj_set(&a, m, "params", p);
    codex_send(m);
    gm_arena_free(&a);

    /* 等待 turn/completed（最多 300 秒） */
    for (int i = 0; i < 3000; i++) {
        if (g_turnDone) return 0;
        if (g_turnInterrupted) {
            if (err) *err = strdup("已中断");
            return -1;
        }
        usleep(100000);
    }
    if (err) *err = strdup("回合超时（5 分钟）");
    return -1;
}

void gm_codex_interrupt(void) {
    if (!g_ready) return;
    g_turnInterrupted = 1;
    GMArena a;
    gm_arena_init(&a, 8192);
    GMPVal *m = gm_val_obj(&a);
    gm_obj_set(&a, m, "id", gm_val_num(&a, g_nextId++));
    gm_obj_set(&a, m, "method", gm_val_str(&a, "turn/interrupt"));
    GMPVal *p = gm_val_obj(&a);
    gm_obj_set(&a, p, "threadId", gm_val_str(&a, g_threadId));
    gm_obj_set(&a, m, "params", p);
    codex_send(m);
    gm_arena_free(&a);
}
