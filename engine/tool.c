/* GM Agent · 工具执行：shell（非阻塞读 + 超时强杀） */
#include "gm_engine.h"
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <errno.h>
#include <poll.h>
#include <time.h>

#define TOOL_OUT_CAP (512 * 1024)

char *gm_tool_run_shell(const char *command, const char *cwd, int timeout_ms, int *code_out) {
    if (code_out) *code_out = -1;
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
        execl("/bin/sh", "sh", "-c", command, (char *)NULL);
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
    return tools;
}
