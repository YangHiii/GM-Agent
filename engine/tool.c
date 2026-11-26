/* GM Agent · 工具执行：shell（非阻塞读 + 超时强杀） */
#include "gm_engine.h"
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <errno.h>
#include <poll.h>
#include <dirent.h>
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
    return tools;
}
