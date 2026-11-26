#include "theos.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/stat.h>

#define TH_BUFSZ 8192

/* 在已安装的运行时里找 theos 根目录（含 makefiles/ 子目录） */
static char *find_theos_root(void) {
    const char *rt = getenv("GM_RUNTIME_DIR");
    if (!rt || !*rt) return NULL;

    char cand[1024];
    const char *names[] = { "theos", "Theos", "theos/theos", NULL };
    for (int i = 0; names[i]; i++) {
        snprintf(cand, sizeof(cand), "%s/%s", rt, names[i]);
        char probe[1100];
        snprintf(probe, sizeof(probe), "%s/makefiles", cand);
        if (access(probe, F_OK) == 0) return strdup(cand);
        snprintf(probe, sizeof(probe), "%s/makefiles/common.mk", cand);
        if (access(probe, F_OK) == 0) return strdup(cand);
    }
    /* 扫一层子目录 */
    char cmd[1200];
    snprintf(cmd, sizeof(cmd), "%s/*/makefiles/common.mk", rt);
    FILE *p = popen("ls -d /dev/null 2>/dev/null", "r");  /* 占位，避免 shell 通配 */
    if (p) pclose(p);
    return NULL;
}

/* 找 make 与 bash（theos 需要 GNU make） */
static const char *find_make(void) {
    const char *rt = getenv("GM_RUNTIME_DIR");
    static char buf[1024];
    if (rt && *rt) {
        const char *dirs[] = { "theos/bin", "build_tools/bin", "core_tools/bin" };
        for (int i = 0; i < 3; i++) {
            snprintf(buf, sizeof(buf), "%s/%s/make", rt, dirs[i]);
            if (access(buf, X_OK) == 0) return buf;
        }
    }
    const char *sys[] = { "/var/jb/usr/bin/make", "/usr/bin/make", "/bin/make", NULL };
    for (int i = 0; sys[i]; i++) if (access(sys[i], X_OK) == 0) return sys[i];
    return "make";
}

static const char *find_bash(void) {
    const char *bundle = getenv("GM_BUNDLE_DIR");
    static char buf[1024];
    if (bundle && *bundle) {
        snprintf(buf, sizeof(buf), "%s/Helpers/bash.real", bundle);
        if (access(buf, X_OK) == 0) return buf;
    }
    const char *sys[] = { "/var/jb/usr/bin/bash", "/bin/bash", "/usr/bin/bash", NULL };
    for (int i = 0; sys[i]; i++) if (access(sys[i], X_OK) == 0) return sys[i];
    return "sh";
}

char *gm_theos_root(void) { return find_theos_root(); }

int gm_theos_available(void) {
    char *r = find_theos_root();
    if (r) { free(r); return 1; }
    return 0;
}

/* 执行并把输出写进 out（调用方释放） */
static int run_capture(const char *cwd, const char *script, char **out, int *code_out) {
    char full[TH_BUFSZ * 2];
    const char *bash = find_bash();
    /* 把 theos 加进 PATH，导出 THEOS */
    char *root = find_theos_root();
    snprintf(full, sizeof(full),
             "cd '%s' 2>/dev/null || exit 97; "
             "%s%s%s "
             "export PATH='%s/bin:%s/usr/bin:$PATH' "
             "export THEOS='%s' "
             "%s 2>&1",
             cwd ? cwd : ".",
             root ? "export THEOS='" : "", root ? root : "", root ? "';" : "",
             root ? root : "/tmp", root ? root : "/tmp",
             root ? root : "",
             script);
    if (root) free(root);

    /* 用 bash -c 执行，捕获输出与退出码 */
    char wrapped[TH_BUFSZ * 3];
    snprintf(wrapped, sizeof(wrapped), "%s -c %s", bash, "x");
    /* 简化：直接 popen，退出码通过追加 echo 捕获 */
    char cmd[TH_BUFSZ * 3];
    snprintf(cmd, sizeof(cmd), "%s -c '%s'; echo \"__RC=$?\"", bash, full);

    FILE *p = popen(cmd, "r");
    if (!p) {
        if (out) *out = strdup("无法启动编译器");
        if (code_out) *code_out = -1;
        return -1;
    }
    char *buf = malloc(256 * 1024);
    if (!buf) { pclose(p); return -1; }
    size_t n = 0;
    int c;
    while ((c = fgetc(p)) != EOF && n < 256 * 1024 - 2) buf[n++] = (char)c;
    buf[n] = 0;
    int rc = pclose(p);

    /* 从尾部提取 __RC= */
    int code = (rc == 0) ? 0 : 1;
    char *m = strrchr(buf, '_');
    if (m) {
        char *eq = strstr(buf, "__RC=");
        if (eq) {
            code = atoi(eq + 5);
            eq[0] = 0;   /* 截断 */
        }
    }
    if (out) *out = buf; else free(buf);
    if (code_out) *code_out = code;
    return 0;
}

/* ---------- 环境准备：make 需要 THEOS 与 SDK ---------- */
static int ensure_env(const char *rust_extra, char **err) {
    (void)rust_extra;
    if (!gm_theos_available()) {
        if (err) *err = strdup("Theos 运行时未安装，请先在「开发能力」里安装 Theos");
        return -1;
    }
    return 0;
}

int gm_theos_build(const char *project_path, const char *target, const char *arch,
                   const char *extra_flags,
                   GMRuntimeProgressFn cb, void *ctx,
                   char **out, int *code_out, char **err) {
    (void)cb; (void)ctx;
    if (ensure_env(NULL, err) != 0) return -1;
    if (!project_path || access(project_path, F_OK) != 0) {
        if (err) *err = strdup("工程目录不存在");
        return -1;
    }

    char script[TH_BUFSZ];
    /* 清理 + 编译；target 形如 package / clean / do */
    const char *tgt = (target && *target) ? target : "package";
    char archflag[64] = "";
    if (arch && *arch) snprintf(archflag, sizeof(archflag), "ARCHS='%s'", arch);
    else snprintf(archflag, sizeof(archflag), "ARCHS=arm64");

    snprintf(script, sizeof(script),
             "make %s %s %s 2>&1 | tail -n 200",
             tgt, archflag, extra_flags ? extra_flags : "");

    return run_capture(project_path, script, out, code_out);
}

int gm_theos_clean(const char *project_path, char **out, int *code_out, char **err) {
    if (ensure_env(NULL, err) != 0) return -1;
    return run_capture(project_path, "make clean 2>&1 | tail -n 50", out, code_out);
}

/* 找编译产物 .deb */
char *gm_theos_find_output(const char *project_path) {
    char cmd[2048];
    char *out = NULL; int code = 0;
    snprintf(cmd, sizeof(cmd),
             "ls -t packages/*.deb 2>/dev/null | head -1; "
             "ls -t .theos/obj/debug/*.deb 2>/dev/null | head -1");
    if (run_capture(project_path, cmd, &out, &code) != 0 || !out) return NULL;
    /* 取第一行 */
    char *nl = strchr(out, '\n');
    if (nl) *nl = 0;
    if (strlen(out) == 0) { free(out); return NULL; }
    return out;
}
