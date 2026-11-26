/* GM Agent · 工具执行：shell（非阻塞读 + 超时强杀） */
#include "gm_engine.h"
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <errno.h>
#include <poll.h>
#include <dirent.h>
#include <sys/stat.h>
#include <time.h>
#include <time.h>

#define TOOL_OUT_CAP (512 * 1024)

/* iOS 上没有 /bin/sh：按越狱/TrollStore/自带 顺序找可用 shell */
static const char *gm_find_shell(void) {
    static char cached[512];
    static int done = 0;
    if (done) return cached[0] ? cached : NULL;
    done = 1;
    /* 仅 Apple 平台用随包 bash（它是 Mach-O，Linux 上跑不了） */
    int apple_platform = access("/System/Library/CoreServices", F_OK) == 0;
    char bundled[512] = {0};
    char exe[1024];
    ssize_t n = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
    (void)n;
    const char *env = getenv("GM_BUNDLE_DIR");
    if (apple_platform && env && *env) {
        snprintf(bundled, sizeof(bundled), "%s/Helpers/bash.real", env);
        if (access(bundled, X_OK) == 0) {
            snprintf(cached, sizeof(cached), "%s", bundled);
            fprintf(stderr, "[gm] shell(bundled): %s\n", cached);
            return cached;
        }
    }
    const char *cands[] = {
        "/var/jb/usr/bin/bash", "/var/jb/usr/bin/sh",
        "/usr/bin/bash", "/usr/bin/sh", "/bin/bash", "/bin/sh",
        "/var/jb/bin/sh",
        NULL
    };
    for (int i = 0; cands[i]; i++) {
        if (access(cands[i], X_OK) == 0) {
            snprintf(cached, sizeof(cached), "%s", cands[i]);
            fprintf(stderr, "[gm] shell: %s\n", cached);
            return cached;
        }
    }
    fprintf(stderr, "[gm] 未找到可用 shell（需越狱/TrollStore 或随包 bash）\n");
    return NULL;
}

static GMHostToolFn g_hostTool = NULL;
void gm_set_host_tool_handler(GMHostToolFn fn) { g_hostTool = fn; }
GMHostToolFn gm_host_tool_handler(void) { return g_hostTool; }

char *gm_tool_run_shell(const char *command, const char *cwd, int timeout_ms, int *code_out) {
    if (code_out) *code_out = -1;
    if (!gm_find_shell()) {
        char *e = strdup("没有可用的 shell：请在越狱/TrollStore 环境安装 bash，或使用随包 bash");
        if (code_out) *code_out = 127;
        return e;
    }
    if (!command || !*command) {
        char *e = malloc(1);
        if (e) e[0] = 0;
        return e;
    }
    int fds[2];
    if (pipe(fds) != 0) return strdup("pipe failed");

    pid_t pid = fork();
    if (pid < 0) {
        close(fds[0]);
        close(fds[1]);
        return strdup("fork failed");
    }
    if (pid == 0) {
        close(fds[0]);
        dup2(fds[1], STDOUT_FILENO);
        dup2(fds[1], STDERR_FILENO);
        close(fds[1]);
        if (cwd && *cwd) { if (chdir(cwd) != 0) _exit(126); }
        setenv("GM_AGENT", "1", 1);
        /* 补上常见 PATH，越狱环境命令多在 /var/jb/usr/bin */
        const char *oldpath = getenv("PATH");
        const char *bundle = getenv("GM_BUNDLE_DIR");
        const char *rtRoot = getenv("GM_RUNTIME_DIR");

        /* 动态收集已安装运行时的可执行目录（Runtimes/<name>/bin） */
        static char rtPaths[2048];
        rtPaths[0] = 0;
        if (rtRoot && *rtRoot) {
            DIR *d = opendir(rtRoot);
            if (d) {
                struct dirent *e;
                size_t off = 0;
                while ((e = readdir(d)) != NULL && off < sizeof(rtPaths) - 512) {
                    if (e->d_name[0] == '.') continue;
                    int n = snprintf(rtPaths + off, sizeof(rtPaths) - off,
                                     "%s/%s/bin:", rtRoot, e->d_name);
                    if (n > 0) off += (size_t)n;
                }
                closedir(d);
            }
        }

        char newpath[4096];
        snprintf(newpath, sizeof(newpath),
                 "%s/Helpers%s%s"
                 "/var/jb/usr/bin:/var/jb/bin:/var/jb/usr/sbin"
                 ":/usr/bin:/bin:/usr/sbin:/sbin"
                 "%s%s",
                 bundle ? bundle : "/tmp",
                 rtPaths[0] ? ":" : "", rtPaths,
                 (oldpath && *oldpath) ? ":" : "",
                 (oldpath && *oldpath) ? oldpath : "");
        setenv("PATH", newpath, 1);

        const char *sh = gm_find_shell();
        if (sh) {
            execl(sh, sh, "-c", command, (char *)NULL);
        }
        /* 退路：直接截断符分割执行第一个词（无 shell 环境） */
        _exit(127);
    }
    close(fds[1]);

    int flags = fcntl(fds[0], F_GETFL, 0);
    fcntl(fds[0], F_SETFL, flags | O_NONBLOCK);

    size_t cap = 8192, len = 0;
    char *out = malloc(cap);
    if (!out) { close(fds[0]); kill(pid, SIGKILL); waitpid(pid, NULL, 0); return NULL; }
    out[0] = 0;

    if (timeout_ms <= 0) timeout_ms = 60000;
    struct timespec t0;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    int truncated = 0, timed_out = 0;

    for (;;) {
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        long long elapsed = (now.tv_sec - t0.tv_sec) * 1000LL + (now.tv_nsec - t0.tv_nsec) / 1000000;
        if (elapsed > timeout_ms) { timed_out = 1; break; }

        struct pollfd pfd = { fds[0], POLLIN, 0 };
        int pr = poll(&pfd, 1, 50);
        if (pr > 0) {
            char chunk[8192];
            ssize_t n = read(fds[0], chunk, sizeof(chunk));
            if (n > 0) {
                if (len + (size_t)n >= TOOL_OUT_CAP) {
                    truncated = 1;
                    n = (ssize_t)(TOOL_OUT_CAP - len - 1);
                }
                if (n > 0) {
                    if (len + (size_t)n + 1 > cap) {
                        while (cap < len + (size_t)n + 1) cap *= 2;
                        char *np = realloc(out, cap);
                        if (!np) break;
                        out = np;
                    }
                    memcpy(out + len, chunk, (size_t)n);
                    len += (size_t)n;
                    out[len] = 0;
                }
                if (truncated) break;
            } else if (n == 0) {
                break;   /* 子进程关闭了管道 */
            }
        } else if (pr == 0) {
            int status = 0;
            pid_t w = waitpid(pid, &status, WNOHANG);
            if (w == pid) {
                /* 进程已退，再排空管道 */
                for (;;) {
                    char chunk[8192];
                    ssize_t n = read(fds[0], chunk, sizeof(chunk));
                    if (n <= 0) break;
                    if (len + (size_t)n + 1 > cap) {
                        while (cap < len + (size_t)n + 1) cap *= 2;
                        char *np = realloc(out, cap);
                        if (!np) break;
                        out = np;
                    }
                    memcpy(out + len, chunk, (size_t)n);
                    len += (size_t)n;
                    out[len] = 0;
                }
                if (code_out) *code_out = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
                close(fds[0]);
                return out;
            }
        }
    }

    if (timed_out) kill(pid, SIGKILL);
    close(fds[0]);
    int status = 0;
    waitpid(pid, &status, 0);
    if (timed_out) {
        const char *msg = "\n[gm] 命令超时，已终止";
        size_t ml = strlen(msg);
        char *np = realloc(out, len + ml + 1);
        if (np) {
            out = np;
            memcpy(out + len, msg, ml + 1);
            len += ml;
        }
    }
    if (truncated) {
        const char *msg = "\n[gm] 输出超限，已截断";
        size_t ml = strlen(msg);
        char *np = realloc(out, len + ml + 1);
        if (np) { out = np; memcpy(out + len, msg, ml + 1); len += ml; }
    }
    if (code_out && !timed_out) *code_out = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    return out;
}


/* ---------- 记忆 / 文件工具 ---------- */

static char *json_field(const char *json, const char *key) {
    if (!json || !key) return NULL;
    char pat[64];
    snprintf(pat, sizeof(pat), "\"%s\"", key);
    const char *p = strstr(json, pat);
    if (!p) return NULL;
    p = strchr(p + strlen(pat), ':');
    if (!p) return NULL;
    p++;
    while (*p == ' ' || *p == '\t') p++;
    if (*p != '"') {
        const char *e = p;
        while (*e && *e != ',' && *e != '}') e++;
        size_t n = (size_t)(e - p);
        char *o = malloc(n + 1);
        if (o) { memcpy(o, p, n); o[n] = 0; }
        return o;
    }
    p++;
    size_t cap = strlen(p) + 8;
    char *o = malloc(cap);
    if (!o) return NULL;
    size_t w = 0;
    const char *q = p;
    while (*q && *q != '"') {
        if (*q == '\\' && q[1]) {
            q++;
            char c = *q;
            o[w++] = (c == 'n') ? '\n' : ((c == 't') ? '\t' : ((c == 'r') ? '\r' : c));
        } else {
            o[w++] = *q;
        }
        q++;
    }
    o[w] = 0;
    return o;
}

static char *memory_path(void) {
    const char *dir = getenv("GM_MEMORY_DIR");
    if (!dir || !*dir) dir = "/var/mobile/.gm";
    static char path[600];
    snprintf(path, sizeof(path), "%s/memory.md", dir);
    return path;
}

static void ensure_dir(const char *dir) {
    char tmp[1024];
    snprintf(tmp, sizeof(tmp), "%s", dir);
    for (char *q = tmp + 1; *q; q++) {
        if (*q == '/') { *q = 0; mkdir(tmp, 0755); *q = '/'; }
    }
    mkdir(tmp, 0755);
}

char *gm_tool_memory_remember(const char *args) {
    char *content = json_field(args, "content");
    if (!content || !*content) { free(content); return strdup("缺少 content"); }
    const char *dir = getenv("GM_MEMORY_DIR");
    if (dir && *dir) ensure_dir(dir);
    FILE *f = fopen(memory_path(), "a");
    if (!f) { free(content); return strdup("无法写入记忆文件"); }
    time_t t = time(NULL);
    struct tm tmv;
    localtime_r(&t, &tmv);
    fprintf(f, "\n- [%04d-%02d-%02d %02d:%02d] %s\n",
            tmv.tm_year + 1900, tmv.tm_mon + 1, tmv.tm_mday,
            tmv.tm_hour, tmv.tm_min, content);
    fclose(f);
    gm_logf("记忆已保存 (%zu 字)", strlen(content));
    free(content);
    return strdup("已记住");
}

char *gm_tool_memory_recall(const char *args) {
    char *query = json_field(args, "query");
    FILE *f = fopen(memory_path(), "r");
    if (!f) { free(query); return strdup("(还没有任何记忆)"); }
    size_t cap = 65536, len = 0;
    char *out = malloc(cap);
    if (!out) { fclose(f); free(query); return strdup("内存不足"); }
    out[0] = 0;
    char line[2048];
    int hits = 0, total = 0;
    while (fgets(line, sizeof(line), f)) {
        total++;
        if (!query || !*query || strstr(line, query)) {
            size_t n = strlen(line);
            if (len + n + 1 < cap) { memcpy(out + len, line, n); len += n; out[len] = 0; }
            hits++;
            if (hits >= 200) break;
        }
    }
    fclose(f);
    free(query);
    if (hits == 0) {
        char msg[128];
        snprintf(msg, sizeof(msg), "(未找到匹配记忆，共 %d 条)", total);
        free(out);
        return strdup(msg);
    }
    return out;
}

char *gm_tool_read_file(const char *args, int *code) {
    char *path = json_field(args, "path");
    if (!path) { if (code) *code = 1; return strdup("缺少 path"); }
    FILE *f = fopen(path, "r");
    if (!f) {
        char msg[600];
        snprintf(msg, sizeof(msg), "无法打开: %s", path);
        free(path);
        if (code) *code = 1;
        return strdup(msg);
    }
    size_t cap = 262144, len = 0;
    char *out = malloc(cap);
    if (!out) { fclose(f); free(path); if (code) *code = 1; return strdup("内存不足"); }
    out[0] = 0;
    char line[4096];
    int n = 0;
    while (fgets(line, sizeof(line), f) && n < 2000) {
        n++;
        char head[24];
        int hn = snprintf(head, sizeof(head), "%5d| ", n);
        size_t ll = strlen(line);
        if (len + (size_t)hn + ll + 1 < cap) {
            memcpy(out + len, head, (size_t)hn); len += (size_t)hn;
            memcpy(out + len, line, ll); len += ll;
            out[len] = 0;
        }
    }
    fclose(f);
    free(path);
    if (code) *code = 0;
    return out;
}

char *gm_tool_write_file(const char *args, int *code) {
    char *path = json_field(args, "path");
    char *content = json_field(args, "content");
    if (!path || !content) {
        free(path); free(content);
        if (code) *code = 1;
        return strdup("缺少 path 或 content");
    }
    FILE *f = fopen(path, "w");
    if (!f) {
        char msg[600];
        snprintf(msg, sizeof(msg), "无法写入: %s", path);
        free(path); free(content);
        if (code) *code = 1;
        return strdup(msg);
    }
    fputs(content, f);
    fclose(f);
    char msg[700];
    snprintf(msg, sizeof(msg), "已写入 %s（%zu 字节）", path, strlen(content));
    free(path); free(content);
    if (code) *code = 0;
    return strdup(msg);
}

char *gm_tool_list_dir(const char *args, int *code) {
    char *path = json_field(args, "path");
    if (!path) { if (code) *code = 1; return strdup("缺少 path"); }
    DIR *d = opendir(path);
    if (!d) {
        char msg[600];
        snprintf(msg, sizeof(msg), "无法打开目录: %s", path);
        free(path);
        if (code) *code = 1;
        return strdup(msg);
    }
    size_t cap = 131072, len = 0;
    char *out = malloc(cap);
    if (!out) { closedir(d); free(path); if (code) *code = 1; return strdup("内存不足"); }
    out[0] = 0;
    struct dirent *e;
    int n = 0;
    while ((e = readdir(d)) != NULL && n < 500) {
        if (strcmp(e->d_name, ".") == 0 || strcmp(e->d_name, "..") == 0) continue;
        char full[1600];
        snprintf(full, sizeof(full), "%s/%s", path, e->d_name);
        struct stat st;
        char kind = '?';
        long long size = 0;
        if (lstat(full, &st) == 0) {
            if (S_ISDIR(st.st_mode)) kind = 'd';
            else if (S_ISLNK(st.st_mode)) kind = 'l';
            else kind = '-';
            size = (long long)st.st_size;
        }
        char line[2200];
        int ln = (kind == 'd')
            ? snprintf(line, sizeof(line), "d %12s  %s/\n", "-", e->d_name)
            : snprintf(line, sizeof(line), "%c %12lld  %s\n", kind, size, e->d_name);
        if (ln > 0 && len + (size_t)ln + 1 < cap) {
            memcpy(out + len, line, (size_t)ln); len += (size_t)ln; out[len] = 0;
        }
        n++;
    }
    closedir(d);
    free(path);
    if (n == 0) { strncat(out, "(空目录)\n", cap - strlen(out) - 1); }
    if (code) *code = 0;
    return out;
}

GMPVal *gm_tool_specs(GMArena *a) {
    GMPVal *tools = gm_val_arr(a);
    GMPVal *t = gm_val_obj(a);
    gm_obj_set(a, t, "type", gm_val_str(a, "function"));
    GMPVal *fn = gm_val_obj(a);
    gm_obj_set(a, fn, "name", gm_val_str(a, "shell"));
    gm_obj_set(a, fn, "description",
               gm_val_str(a, "在本机 shell 中执行命令并返回输出。用于读写文件、构建、运行测试等。"));
    GMPVal *params = gm_val_obj(a);
    gm_obj_set(a, params, "type", gm_val_str(a, "object"));
    GMPVal *props = gm_val_obj(a);
    GMPVal *cmd = gm_val_obj(a);
    gm_obj_set(a, cmd, "type", gm_val_str(a, "string"));
    gm_obj_set(a, cmd, "description", gm_val_str(a, "要执行的命令（sh -c）"));
    gm_obj_set(a, props, "command", cmd);
    GMPVal *cwd = gm_val_obj(a);
    gm_obj_set(a, cwd, "type", gm_val_str(a, "string"));
    gm_obj_set(a, cwd, "description", gm_val_str(a, "工作目录，可选"));
    gm_obj_set(a, props, "cwd", cwd);
    gm_obj_set(a, params, "properties", props);
    GMPVal *req = gm_val_arr(a);
    gm_arr_push(a, req, gm_val_str(a, "command"));
    gm_obj_set(a, params, "required", req);
    gm_obj_set(a, fn, "parameters", params);
    gm_obj_set(a, t, "function", fn);
    gm_arr_push(a, tools, t);

    /* open_app：由 App 侧用 LSApplicationWorkspace 执行 */
    GMPVal *t2 = gm_val_obj(a);
    gm_obj_set(a, t2, "type", gm_val_str(a, "function"));
    GMPVal *fn2 = gm_val_obj(a);
    gm_obj_set(a, fn2, "name", gm_val_str(a, "open_app"));
    gm_obj_set(a, fn2, "description",
               gm_val_str(a, "打开 iOS 上的应用。参数 name 为应用名（如 红果短剧）或 bundle id。"));
    GMPVal *p2 = gm_val_obj(a);
    gm_obj_set(a, p2, "type", gm_val_str(a, "object"));
    GMPVal *pr2 = gm_val_obj(a);
    GMPVal *nm = gm_val_obj(a);
    gm_obj_set(a, nm, "type", gm_val_str(a, "string"));
    gm_obj_set(a, nm, "description", gm_val_str(a, "应用名或 bundle id"));
    gm_obj_set(a, pr2, "name", nm);
    gm_obj_set(a, p2, "properties", pr2);
    GMPVal *rq2 = gm_val_arr(a);
    gm_arr_push(a, rq2, gm_val_str(a, "name"));
    gm_obj_set(a, p2, "required", rq2);
    gm_obj_set(a, fn2, "parameters", p2);
    gm_obj_set(a, t2, "function", fn2);
    gm_arr_push(a, tools, t2);

    /* 记忆：保存 */
    GMPVal *t3 = gm_val_obj(a);
    gm_obj_set(a, t3, "type", gm_val_str(a, "function"));
    GMPVal *f3 = gm_val_obj(a);
    gm_obj_set(a, f3, "name", gm_val_str(a, "memory_remember"));
    gm_obj_set(a, f3, "description", gm_val_str(a, "把重要事实写入长期记忆（跨会话保留）。"));
    GMPVal *p3 = gm_val_obj(a);
    gm_obj_set(a, p3, "type", gm_val_str(a, "object"));
    GMPVal *pr3 = gm_val_obj(a);
    GMPVal *c3 = gm_val_obj(a);
    gm_obj_set(a, c3, "type", gm_val_str(a, "string"));
    gm_obj_set(a, c3, "description", gm_val_str(a, "要记住的内容"));
    gm_obj_set(a, pr3, "content", c3);
    gm_obj_set(a, p3, "properties", pr3);
    GMPVal *r3 = gm_val_arr(a);
    gm_arr_push(a, r3, gm_val_str(a, "content"));
    gm_obj_set(a, p3, "required", r3);
    gm_obj_set(a, f3, "parameters", p3);
    gm_obj_set(a, t3, "function", f3);
    gm_arr_push(a, tools, t3);

    /* 记忆：检索 */
    GMPVal *t4 = gm_val_obj(a);
    gm_obj_set(a, t4, "type", gm_val_str(a, "function"));
    GMPVal *f4 = gm_val_obj(a);
    gm_obj_set(a, f4, "name", gm_val_str(a, "memory_recall"));
    gm_obj_set(a, f4, "description", gm_val_str(a, "按关键词检索长期记忆。"));
    GMPVal *p4 = gm_val_obj(a);
    gm_obj_set(a, p4, "type", gm_val_str(a, "object"));
    GMPVal *pr4 = gm_val_obj(a);
    GMPVal *c4 = gm_val_obj(a);
    gm_obj_set(a, c4, "type", gm_val_str(a, "string"));
    gm_obj_set(a, c4, "description", gm_val_str(a, "关键词，空则返回最近记忆"));
    gm_obj_set(a, pr4, "query", c4);
    gm_obj_set(a, p4, "properties", pr4);
    gm_obj_set(a, f4, "parameters", p4);
    gm_obj_set(a, t4, "function", f4);
    gm_arr_push(a, tools, t4);

    /* 文件读取 */
    GMPVal *t5 = gm_val_obj(a);
    gm_obj_set(a, t5, "type", gm_val_str(a, "function"));
    GMPVal *f5 = gm_val_obj(a);
    gm_obj_set(a, f5, "name", gm_val_str(a, "read_file"));
    gm_obj_set(a, f5, "description", gm_val_str(a, "读取文本文件内容（带行号，最多 2000 行）。"));
    GMPVal *p5 = gm_val_obj(a);
    gm_obj_set(a, p5, "type", gm_val_str(a, "object"));
    GMPVal *pr5 = gm_val_obj(a);
    GMPVal *c5 = gm_val_obj(a);
    gm_obj_set(a, c5, "type", gm_val_str(a, "string"));
    gm_obj_set(a, c5, "description", gm_val_str(a, "文件绝对路径"));
    gm_obj_set(a, pr5, "path", c5);
    gm_obj_set(a, p5, "properties", pr5);
    GMPVal *r5 = gm_val_arr(a);
    gm_arr_push(a, r5, gm_val_str(a, "path"));
    gm_obj_set(a, p5, "required", r5);
    gm_obj_set(a, f5, "parameters", p5);
    gm_obj_set(a, t5, "function", f5);
    gm_arr_push(a, tools, t5);

    /* 文件写入 */
    GMPVal *t6 = gm_val_obj(a);
    gm_obj_set(a, t6, "type", gm_val_str(a, "function"));
    GMPVal *f6 = gm_val_obj(a);
    gm_obj_set(a, f6, "name", gm_val_str(a, "write_file"));
    gm_obj_set(a, f6, "description", gm_val_str(a, "把内容写入文件（覆盖）。"));
    GMPVal *p6 = gm_val_obj(a);
    gm_obj_set(a, p6, "type", gm_val_str(a, "object"));
    GMPVal *pr6 = gm_val_obj(a);
    GMPVal *c6a = gm_val_obj(a);
    gm_obj_set(a, c6a, "type", gm_val_str(a, "string"));
    gm_obj_set(a, c6a, "description", gm_val_str(a, "文件绝对路径"));
    gm_obj_set(a, pr6, "path", c6a);
    GMPVal *c6b = gm_val_obj(a);
    gm_obj_set(a, c6b, "type", gm_val_str(a, "string"));
    gm_obj_set(a, c6b, "description", gm_val_str(a, "文件内容"));
    gm_obj_set(a, pr6, "content", c6b);
    gm_obj_set(a, p6, "properties", pr6);
    GMPVal *r6 = gm_val_arr(a);
    gm_arr_push(a, r6, gm_val_str(a, "path"));
    gm_arr_push(a, r6, gm_val_str(a, "content"));
    gm_obj_set(a, p6, "required", r6);
    gm_obj_set(a, f6, "parameters", p6);
    gm_obj_set(a, t6, "function", f6);
    gm_arr_push(a, tools, t6);

    /* 目录列表 */
    GMPVal *t7 = gm_val_obj(a);
    gm_obj_set(a, t7, "type", gm_val_str(a, "function"));
    GMPVal *f7 = gm_val_obj(a);
    gm_obj_set(a, f7, "name", gm_val_str(a, "list_dir"));
    gm_obj_set(a, f7, "description", gm_val_str(a, "列出目录内容（名称/类型/大小）。"));
    GMPVal *p7 = gm_val_obj(a);
    gm_obj_set(a, p7, "type", gm_val_str(a, "object"));
    GMPVal *pr7 = gm_val_obj(a);
    GMPVal *c7 = gm_val_obj(a);
    gm_obj_set(a, c7, "type", gm_val_str(a, "string"));
    gm_obj_set(a, c7, "description", gm_val_str(a, "目录路径"));
    gm_obj_set(a, pr7, "path", c7);
    gm_obj_set(a, p7, "properties", pr7);
    GMPVal *r7 = gm_val_arr(a);
    gm_arr_push(a, r7, gm_val_str(a, "path"));
    gm_obj_set(a, p7, "required", r7);
    gm_obj_set(a, f7, "parameters", p7);
    gm_obj_set(a, t7, "function", f7);
    gm_arr_push(a, tools, t7);

    return tools;
}
