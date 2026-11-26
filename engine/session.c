/* GM Agent · 会话存储（JSONL 追加，历史读取用独立 arena） */
#include "gm_engine.h"
#include <sys/stat.h>
#include <unistd.h>

struct GMSession {
    char id[64];
    char path[600];
};

static void mkdirs(const char *path) {
    char tmp[600];
    snprintf(tmp, sizeof(tmp), "%s", path);
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') { *p = 0; mkdir(tmp, 0755); *p = '/'; }
    }
    mkdir(tmp, 0755);
}

GMSession *gm_session_new(const char *thread_id) {
    GMSession *s = calloc(1, sizeof(GMSession));
    if (!s) return NULL;
    snprintf(s->id, sizeof(s->id), "%.40s", thread_id ? thread_id : "default");
    char dir[512];
    const char *envDir = getenv("GM_SESSION_DIR");
    if (envDir && *envDir) {
        snprintf(dir, sizeof(dir), "%.480s", envDir);
    } else {
        const char *home = getenv("HOME");
        if (!home) home = "/var/mobile";
        snprintf(dir, sizeof(dir), "%.480s/.gm/sessions", home);
    }
    mkdirs(dir);
    snprintf(s->path, sizeof(s->path), "%.480s/%.40s.jsonl", dir, s->id);
    /* 立即创建空文件，便于后续 append 与 history 读取 */
    FILE *f = fopen(s->path, "a");
    if (f) fclose(f);
    return s;
}

void gm_session_free(GMSession *s) { free(s); }
const char *gm_session_id(const GMSession *s) { return s ? s->id : ""; }

/* 统一计算会话 JSONL 路径 */
static void gm_session_path(const char *thread_id, char *out, size_t cap) {
    char dir[512];
    const char *envDir = getenv("GM_SESSION_DIR");
    if (envDir && *envDir) {
        snprintf(dir, sizeof(dir), "%.480s", envDir);
    } else {
        const char *home = getenv("HOME");
        if (!home) home = "/var/mobile";
        snprintf(dir, sizeof(dir), "%.480s/.gm/sessions", home);
    }
    snprintf(out, cap, "%.460s/%.40s.jsonl", dir, thread_id ? thread_id : "default");
}

GMPVal *gm_session_load_history(const char *thread_id, GMArena *a) {
    GMPVal *arr = gm_val_arr(a);
    if (!thread_id || !*thread_id) return arr;
    char path[600];
    gm_session_path(thread_id, path, sizeof(path));
    FILE *f = fopen(path, "r");
    if (!f) return arr;
    char line[8192];
    while (fgets(line, sizeof(line), f)) {
        size_t n = strlen(line);
        while (n && (line[n-1] == '\n' || line[n-1] == '\r')) line[--n] = 0;
        if (!n) continue;
        GMPVal *v = gm_parse(a, line, n);
        if (v && v->t == GM_OBJ) gm_arr_push(a, arr, v);
    }
    fclose(f);
    return arr;
}

int gm_session_exists(const char *thread_id) {
    if (!thread_id || !*thread_id) return 0;
    char path[600];
    gm_session_path(thread_id, path, sizeof(path));
    return access(path, R_OK) == 0;
}

void gm_session_append(GMSession *s, const char *role, const char *text) {
    if (!s) return;
    FILE *f = fopen(s->path, "a");
    if (!f) return;
    GMArena a;
    gm_arena_init(&a, 65536);
    GMPVal *m = gm_val_obj(&a);
    gm_obj_set(&a, m, "role", gm_val_str(&a, role));
    gm_obj_set(&a, m, "content", gm_val_str(&a, text ? text : ""));
    GMBuf b;
    gm_buf_init(&b, &a, 4096);
    gm_write_val(&b, m);
    fwrite(b.p, 1, b.len, f);
    fputc('\n', f);
    fclose(f);
    gm_arena_free(&a);
}

void gm_session_append_user(GMSession *s, const char *text) { gm_session_append(s, "user", text); }
void gm_session_append_assistant(GMSession *s, const char *text) { gm_session_append(s, "assistant", text); }
