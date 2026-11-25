/* GM Agent · 零依赖 JSON（区域分配器，绝无 free）
 * 设计目标：
 *  1. 解析永不失败崩溃——输入不合法直接返回 NULL
 *  2. 所有内存来自两个 bump arena（临时/输出），统一释放，杜绝 double-free
 *     （iSH 环境下 glibc free() double-free 会直接 SIGSEGV，无诊断信息）
 */
#include "gm_engine.h"

void gm_arena_init(GMArena *a, size_t cap) {
    if (!a) return;
    a->p = cap ? malloc(cap) : NULL;
    a->len = 0;
    a->cap = cap;
}

void gm_arena_reset(GMArena *a) { if (a) a->len = 0; }

void gm_arena_free(GMArena *a) {
    if (!a) return;
    free(a->p);
    a->p = NULL;
    a->len = a->cap = 0;
}

static void *arena_alloc(GMArena *a, size_t n) {
    if (!a || !a->p) return NULL;
    n = (n + 15) & ~(size_t)15;
    if (a->len + n > a->cap) return NULL;
    void *p = a->p + a->len;
    memset(p, 0, n);
    a->len += n;
    return p;
}

static char *arena_str(GMArena *a, const char *s, size_t n) {
    char *p = arena_alloc(a, n + 1);
    if (!p) return NULL;
    if (n) memcpy(p, s, n);
    p[n] = 0;
    return p;
}

/* ---------- 动态 buffer（也走输出 arena） ---------- */
void gm_buf_init(GMBuf *b, GMArena *arena, size_t cap) {
    b->p = arena_alloc(arena, cap ? cap : 256);
    b->len = 0;
    b->cap = b->p ? (cap ? cap : 256) : 0;
    b->arena = arena;
}

static void buf_reserve(GMBuf *b, size_t need) {
    if (b->len + need + 1 <= b->cap) return;
    /* 单块 arena 不能扩，改为整块拷贝到 arena 新块 */
    size_t newcap = b->cap ? b->cap * 2 : 256;
    while (newcap < b->len + need + 1) newcap *= 2;
    char *np = arena_alloc(b->arena, newcap);
    if (!np) return;
    if (b->p) memcpy(np, b->p, b->len);
    b->p = np;
    b->cap = newcap;
}

void gm_buf_append(GMBuf *b, const char *data, size_t n) {
    if (!b || !b->p || !data) return;
    buf_reserve(b, n);
    if (b->len + n + 1 > b->cap) return;
    memcpy(b->p + b->len, data, n);
    b->len += n;
    b->p[b->len] = 0;
}

void gm_buf_puts(GMBuf *b, const char *s) { if (s) gm_buf_append(b, s, strlen(s)); }

void gm_buf_printf(GMBuf *b, const char *fmt, ...) {
    char tmp[2048];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(tmp, sizeof(tmp), fmt, ap);
    va_end(ap);
    if (n > 0 && (size_t)n < sizeof(tmp)) gm_buf_append(b, tmp, (size_t)n);
}

/* ---------- DOM ---------- */
GMPVal *gm_val_obj(GMArena *a) { GMPVal *v = arena_alloc(a, sizeof *v); if (v) v->t = GM_OBJ; return v; }
GMPVal *gm_val_arr(GMArena *a) { GMPVal *v = arena_alloc(a, sizeof *v); if (v) v->t = GM_ARR; return v; }
GMPVal *gm_val_null(GMArena *a) { GMPVal *v = arena_alloc(a, sizeof *v); if (v) v->t = GM_NULL; return v; }
GMPVal *gm_val_true(GMArena *a, int b) {
    GMPVal *v = arena_alloc(a, sizeof *v);
    if (v) { v->t = GM_BOOL; v->u.b = b ? 1 : 0; }
    return v;
}
GMPVal *gm_val_num(GMArena *a, double d) {
    GMPVal *v = arena_alloc(a, sizeof *v);
    if (v) { v->t = GM_NUM; v->u.n = d; }
    return v;
}
GMPVal *gm_val_str(GMArena *a, const char *s) {
    GMPVal *v = arena_alloc(a, sizeof *v);
    if (!v) return NULL;
    v->t = GM_STR;
    size_t n = s ? strlen(s) : 0;
    v->u.s.p = arena_str(a, s ? s : "", n);
    return v;
}
GMPVal *gm_val_strn(GMArena *a, const char *s, size_t n) {
    GMPVal *v = arena_alloc(a, sizeof *v);
    if (!v) return NULL;
    v->t = GM_STR;
    v->u.s.p = arena_str(a, s, n);
    return v;
}

void gm_arr_push(GMArena *a, GMPVal *arr, GMPVal *val) {
    if (!arr || arr->t != GM_ARR) return;
    GMPVal **items = arena_alloc(a, sizeof(GMPVal *) * (arr->u.a.count + 1));
    if (!items) return;
    for (size_t i = 0; i < arr->u.a.count; i++) items[i] = arr->u.a.items[i];
    items[arr->u.a.count] = val;
    arr->u.a.items = items;
    arr->u.a.count++;
}

void gm_obj_set(GMArena *a, GMPVal *obj, const char *key, GMPVal *val) {
    if (!obj || obj->t != GM_OBJ || !key) return;
    for (size_t i = 0; i < obj->u.o.count; i++) {
        if (obj->u.o.keys[i] && strcmp(obj->u.o.keys[i], key) == 0) {
            obj->u.o.vals[i] = val;
            return;
        }
    }
    char **keys = arena_alloc(a, sizeof(char *) * (obj->u.o.count + 1));
    GMPVal **vals = arena_alloc(a, sizeof(GMPVal *) * (obj->u.o.count + 1));
    if (!keys || !vals) return;
    for (size_t i = 0; i < obj->u.o.count; i++) {
        keys[i] = obj->u.o.keys[i];
        vals[i] = obj->u.o.vals[i];
    }
    keys[obj->u.o.count] = arena_str(a, key, strlen(key));
    vals[obj->u.o.count] = val;
    obj->u.o.keys = keys;
    obj->u.o.vals = vals;
    obj->u.o.count++;
}

GMPVal *gm_obj_get(const GMPVal *obj, const char *key) {
    if (!obj || obj->t != GM_OBJ || !key) return NULL;
    for (size_t i = 0; i < obj->u.o.count; i++)
        if (obj->u.o.keys[i] && strcmp(obj->u.o.keys[i], key) == 0) return obj->u.o.vals[i];
    return NULL;
}

const char *gm_str(const GMPVal *v) { return (v && v->t == GM_STR) ? v->u.s.p : NULL; }
double gm_num(const GMPVal *v, double dflt) { return (v && v->t == GM_NUM) ? v->u.n : dflt; }
int gm_bool(const GMPVal *v, int dflt) { return (v && v->t == GM_BOOL) ? v->u.b : dflt; }
size_t gm_arr_count(const GMPVal *v) { return (v && v->t == GM_ARR) ? v->u.a.count : 0; }
GMPVal *gm_arr_at(const GMPVal *v, size_t i) {
    return (v && v->t == GM_ARR && i < v->u.a.count) ? v->u.a.items[i] : NULL;
}

/* ---------- 解析 ---------- */
typedef struct { const char *s; size_t len; size_t i; GMArena *a; int depth; } P;

static void skip_ws(P *p) {
    while (p->i < p->len) {
        char c = p->s[p->i];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') p->i++;
        else break;
    }
}

static void utf8(char *out, size_t *n, unsigned cp) {
    if (cp < 0x80) out[(*n)++] = (char)cp;
    else if (cp < 0x800) {
        out[(*n)++] = (char)(0xC0 | (cp >> 6));
        out[(*n)++] = (char)(0x80 | (cp & 0x3F));
    } else {
        out[(*n)++] = (char)(0xE0 | (cp >> 12));
        out[(*n)++] = (char)(0x80 | ((cp >> 6) & 0x3F));
        out[(*n)++] = (char)(0x80 | (cp & 0x3F));
    }
}

/* 返回 arena 内字符串；失败 NULL。*outlen 为字节长度 */
static char *parse_str(P *p, size_t *outlen) {
    if (p->i >= p->len || p->s[p->i] != '"') return NULL;
    p->i++;
    /* 先测量 */
    size_t n = 0;
    size_t scan = p->i;
    while (scan < p->len) {
        char c = p->s[scan];
        if (c == '"') break;
        if (c == '\\') { scan += 2; n++; continue; }
        scan++; n++;
    }
    if (scan >= p->len) return NULL;
    char *out = arena_alloc(p->a, n * 3 + 4);
    if (!out) return NULL;
    size_t w = 0;
    while (p->i < p->len) {
        char c = p->s[p->i];
        if (c == '"') { p->i++; out[w] = 0; *outlen = w; return out; }
        if (c == '\\') {
            p->i++;
            if (p->i >= p->len) return NULL;
            char e = p->s[p->i];
            switch (e) {
                case '"': out[w++] = '"'; break;
                case '\\': out[w++] = '\\'; break;
                case '/': out[w++] = '/'; break;
                case 'b': out[w++] = '\b'; break;
                case 'f': out[w++] = '\f'; break;
                case 'n': out[w++] = '\n'; break;
                case 'r': out[w++] = '\r'; break;
                case 't': out[w++] = '\t'; break;
                case 'u': {
                    if (p->i + 4 >= p->len) return NULL;
                    unsigned cp = 0; int ok = 1;
                    for (int k = 1; k <= 4; k++) {
                        char h = p->s[p->i + k];
                        cp <<= 4;
                        if (h >= '0' && h <= '9') cp |= (unsigned)(h - '0');
                        else if (h >= 'a' && h <= 'f') cp |= (unsigned)(h - 'a' + 10);
                        else if (h >= 'A' && h <= 'F') cp |= (unsigned)(h - 'A' + 10);
                        else { ok = 0; break; }
                    }
                    if (!ok) return NULL;
                    p->i += 4;
                    /* 代理对 */
                    if (cp >= 0xD800 && cp <= 0xDBFF && p->i + 6 < p->len &&
                        p->s[p->i + 1] == '\\' && p->s[p->i + 2] == 'u') {
                        unsigned lo = 0; int ok2 = 1;
                        for (int k = 3; k <= 6; k++) {
                            char h = p->s[p->i + k];
                            lo <<= 4;
                            if (h >= '0' && h <= '9') lo |= (unsigned)(h - '0');
                            else if (h >= 'a' && h <= 'f') lo |= (unsigned)(h - 'a' + 10);
                            else if (h >= 'A' && h <= 'F') lo |= (unsigned)(h - 'A' + 10);
                            else { ok2 = 0; break; }
                        }
                        if (ok2 && lo >= 0xDC00 && lo <= 0xDFFF) {
                            cp = 0x10000 + (((cp - 0xD800) << 10) | (lo - 0xDC00));
                            p->i += 6;
                        }
                    }
                    utf8(out, &w, cp);
                    break;
                }
                default: out[w++] = e; break;
            }
            p->i++;
            continue;
        }
        out[w++] = c;
        p->i++;
    }
    return NULL;
}

static GMPVal *parse_val(P *p);

static GMPVal *parse_num(P *p) {
    size_t st = p->i;
    while (p->i < p->len) {
        char c = p->s[p->i];
        if ((c >= '0' && c <= '9') || c == '-' || c == '+' || c == '.' || c == 'e' || c == 'E') p->i++;
        else break;
    }
    if (p->i == st || p->i - st > 60) return NULL;
    char tmp[64];
    memcpy(tmp, p->s + st, p->i - st);
    tmp[p->i - st] = 0;
    return gm_val_num(p->a, strtod(tmp, NULL));
}

static GMPVal *parse_val(P *p) {
    if (++p->depth > 200) return NULL;
    skip_ws(p);
    if (p->i >= p->len) return NULL;
    char c = p->s[p->i];
    GMPVal *v = NULL;
    if (c == '{') {
        p->i++;
        v = gm_val_obj(p->a);
        if (!v) return NULL;
        skip_ws(p);
        if (p->i < p->len && p->s[p->i] == '}') { p->i++; p->depth--; return v; }
        while (p->i < p->len) {
            skip_ws(p);
            size_t klen = 0;
            char *k = parse_str(p, &klen);
            if (!k) return NULL;
            skip_ws(p);
            if (p->i >= p->len || p->s[p->i] != ':') return NULL;
            p->i++;
            GMPVal *child = parse_val(p);
            if (!child) return NULL;
            gm_obj_set(p->a, v, k, child);
            skip_ws(p);
            if (p->i < p->len && p->s[p->i] == ',') { p->i++; continue; }
            if (p->i < p->len && p->s[p->i] == '}') { p->i++; p->depth--; return v; }
            return NULL;
        }
        return NULL;
    }
    if (c == '[') {
        p->i++;
        v = gm_val_arr(p->a);
        if (!v) return NULL;
        skip_ws(p);
        if (p->i < p->len && p->s[p->i] == ']') { p->i++; p->depth--; return v; }
        while (p->i < p->len) {
            GMPVal *child = parse_val(p);
            if (!child) return NULL;
            gm_arr_push(p->a, v, child);
            skip_ws(p);
            if (p->i < p->len && p->s[p->i] == ',') { p->i++; continue; }
            if (p->i < p->len && p->s[p->i] == ']') { p->i++; p->depth--; return v; }
            return NULL;
        }
        return NULL;
    }
    if (c == '"') {
        size_t n = 0;
        char *s = parse_str(p, &n);
        if (!s) return NULL;
        v = gm_val_strn(p->a, s, n);
        p->depth--;
        return v;
    }
    if (p->len - p->i >= 4 && strncmp(p->s + p->i, "true", 4) == 0) { p->i += 4; p->depth--; return gm_val_true(p->a, 1); }
    if (p->len - p->i >= 5 && strncmp(p->s + p->i, "false", 5) == 0) { p->i += 5; p->depth--; return gm_val_true(p->a, 0); }
    if (p->len - p->i >= 4 && strncmp(p->s + p->i, "null", 4) == 0) { p->i += 4; p->depth--; return gm_val_null(p->a); }
    v = parse_num(p);
    p->depth--;
    return v;
}

GMPVal *gm_parse(GMArena *a, const char *json, size_t len) {
    if (!a || !a->p || !json) return NULL;
    P p = { json, len, 0, a, 0 };
    return parse_val(&p);
}

/* ---------- 序列化 ---------- */
static void write_str(GMBuf *b, const char *s, size_t n) {
    gm_buf_append(b, "\"", 1);
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)s[i];
        switch (c) {
            case '"': gm_buf_append(b, "\\\"", 2); break;
            case '\\': gm_buf_append(b, "\\\\", 2); break;
            case '\n': gm_buf_append(b, "\\n", 2); break;
            case '\r': gm_buf_append(b, "\\r", 2); break;
            case '\t': gm_buf_append(b, "\\t", 2); break;
            default:
                if (c < 0x20) gm_buf_printf(b, "\\u%04x", c);
                else gm_buf_append(b, (const char *)&c, 1);
        }
    }
    gm_buf_append(b, "\"", 1);
}

void gm_write_val(GMBuf *b, const GMPVal *v) {
    if (!b || !b->p) return;
    if (!v) { gm_buf_puts(b, "null"); return; }
    switch (v->t) {
        case GM_NULL: gm_buf_puts(b, "null"); break;
        case GM_BOOL: gm_buf_puts(b, v->u.b ? "true" : "false"); break;
        case GM_NUM: {
            double d = v->u.n;
            if (d == (double)(long long)d) gm_buf_printf(b, "%lld", (long long)d);
            else gm_buf_printf(b, "%.10g", d);
            break;
        }
        case GM_STR:
            write_str(b, v->u.s.p ? v->u.s.p : "", v->u.s.p ? strlen(v->u.s.p) : 0);
            break;
        case GM_ARR:
            gm_buf_puts(b, "[");
            for (size_t i = 0; i < v->u.a.count; i++) {
                if (i) gm_buf_puts(b, ",");
                gm_write_val(b, v->u.a.items[i]);
            }
            gm_buf_puts(b, "]");
            break;
        case GM_OBJ:
            gm_buf_puts(b, "{");
            for (size_t i = 0; i < v->u.o.count; i++) {
                if (i) gm_buf_puts(b, ",");
                write_str(b, v->u.o.keys[i], strlen(v->u.o.keys[i]));
                gm_buf_puts(b, ":");
                gm_write_val(b, v->u.o.vals[i]);
            }
            gm_buf_puts(b, "}");
            break;
    }
}
