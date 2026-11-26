/* GM Agent · 运行时安装器实现 */
#include "runtime.h"
#include "http.h"

#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <zlib.h>
#include <openssl/evp.h>

static void seterr(char **err, const char *fmt, ...) {
    if (!err) return;
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    *err = strdup(buf);
}

static int mkdir_p(const char *path) {
    char tmp[1024];
    snprintf(tmp, sizeof(tmp), "%s", path);
    size_t n = strlen(tmp);
    while (n > 1 && tmp[n - 1] == '/') tmp[--n] = 0;
    for (char *p = tmp + 1; *p; p++) {
        if (*p != '/') continue;
        *p = 0;
        if (mkdir(tmp, 0755) != 0 && errno != EEXIST) return -1;
        *p = '/';
    }
    if (mkdir(tmp, 0755) != 0 && errno != EEXIST) return -1;
    return 0;
}

/* ---------- tar 解析 ---------- */

typedef struct {
    char name[100];
    char mode[8];
    char uid[8];
    char gid[8];
    char size[12];
    char mtime[12];
    char chksum[8];
    char typeflag;
    char linkname[100];
    char magic[6];
    char version[2];
    char uname[32];
    char gname[32];
    char devmajor[8];
    char devminor[8];
    char prefix[155];
    char pad[12];
} GMTarHeader;

static long long tar_octal(const char *s, int len) {
    long long v = 0;
    for (int i = 0; i < len && s[i]; i++) {
        char c = s[i];
        if (c == ' ') continue;
        if (c < '0' || c > '7') break;
        v = v * 8 + (c - '0');
    }
    return v;
}

static int write_full(int fd, const char *buf, size_t len) {
    size_t off = 0;
    while (off < len) {
        ssize_t n = write(fd, buf + off, len - off);
        if (n <= 0) return -1;
        off += (size_t)n;
    }
    return 0;
}

/* 从 gz 流中读满 n 字节；返回实际读取字节数 */
static size_t gz_read_full(gzFile gz, char *buf, size_t n) {
    size_t got = 0;
    while (got < n) {
        int r = gzread(gz, buf + got, (unsigned)(n - got));
        if (r <= 0) break;
        got += (size_t)r;
    }
    return got;
}

int gm_tar_gz_extract(const char *archive, const char *destDir, char **err) {
    gzFile gz = gzopen(archive, "rb");
    if (!gz) { seterr(err, "无法打开压缩包: %s", archive); return -1; }
    if (mkdir_p(destDir) != 0) { gzclose(gz); seterr(err, "无法创建目录: %s", destDir); return -1; }

    GMTarHeader hdr;
    char longname[2048] = {0};
    char *buf = malloc(64 * 1024);
    if (!buf) { gzclose(gz); seterr(err, "内存不足"); return -1; }

    int rc = 0;
    while (1) {
        size_t got = gz_read_full(gz, (char *)&hdr, sizeof(hdr));
        if (got < sizeof(hdr)) break;
        if (hdr.name[0] == 0) break;   /* 结束标记 */
        long long size = tar_octal(hdr.size, sizeof(hdr.size));
        char mode = hdr.typeflag ? hdr.typeflag : '0';

        /* 长文件名（GNU） */
        if (mode == 'L') {
            size_t n = (size_t)size > sizeof(longname) - 1 ? sizeof(longname) - 1 : (size_t)size;
            gz_read_full(gz, longname, n);
            longname[n] = 0;
            long long skip = size - (long long)n;
            long long pad = (512 - (size % 512)) % 512;
            if (skip > 0) gzseek(gz, (long)skip, SEEK_CUR);
            if (pad > 0) gzseek(gz, (long)pad, SEEK_CUR);
            continue;
        }
        /* pax 头：直接跳过 */
        if (mode == 'x' || mode == 'g') {
            long long pad = (512 - (size % 512)) % 512;
            if (size > 0) gzseek(gz, (long)size, SEEK_CUR);
            if (pad > 0) gzseek(gz, (long)pad, SEEK_CUR);
            continue;
        }

        char full[2048];
        if (longname[0]) {
            snprintf(full, sizeof(full), "%s/%s", destDir, longname);
            longname[0] = 0;
        } else {
            char nm[256];
            if (hdr.prefix[0]) snprintf(nm, sizeof(nm), "%.155s/%.100s", hdr.prefix, hdr.name);
            else snprintf(nm, sizeof(nm), "%.100s", hdr.name);
            /* 去掉以 ./ 开头 */
            const char *p = nm;
            while (p[0] == '.' && p[1] == '/') p += 2;
            if (!*p) { continue; }
            snprintf(full, sizeof(full), "%s/%s", destDir, p);
        }

        long md = tar_octal(hdr.mode, sizeof(hdr.mode));
        if (md == 0) md = (mode == '5') ? 0755 : 0644;

        if (mode == '5') {                    /* 目录 */
            mkdir_p(full);
        } else if (mode == '2') {             /* 符号链接 */
            char target[256];
            snprintf(target, sizeof(target), "%.100s", hdr.linkname);
            unlink(full);
            if (symlink(target, full) != 0) {
                /* iSH/受限环境：写成普通文件内容，避免整体失败 */
                int fd = open(full, O_CREAT | O_WRONLY | O_TRUNC, 0644);
                if (fd >= 0) { write_full(fd, target, strlen(target)); close(fd); }
            }
        } else {                              /* 普通文件 */
            char dir[1024];
            snprintf(dir, sizeof(dir), "%s", full);
            char *slash = strrchr(dir, '/');
            if (slash) { *slash = 0; mkdir_p(dir); }
            int fd = open(full, O_CREAT | O_WRONLY | O_TRUNC, (int)(md & 0777));
            if (fd < 0) {
                long long pad = (512 - (size % 512)) % 512;
                if (size > 0) gzseek(gz, (long)size, SEEK_CUR);
                if (pad > 0) gzseek(gz, (long)pad, SEEK_CUR);
                continue;
            }
            long long left = size;
            while (left > 0) {
                size_t want = (size_t)(left > 64 * 1024 ? 64 * 1024 : left);
                size_t n = gz_read_full(gz, buf, want);
                if (n == 0) break;
                write_full(fd, buf, n);
                left -= (long long)n;
            }
            close(fd);
            chmod(full, (mode_t)(md & 0777));
        }

        long long pad = (512 - (size % 512)) % 512;
        if (pad > 0) gzseek(gz, (long)pad, SEEK_CUR);
    }

    free(buf);
    gzclose(gz);
    return rc;
}

/* ---------- deb（ar 容器） ---------- */

int gm_deb_extract(const char *archive, const char *destDir, char **err) {
    FILE *f = fopen(archive, "rb");
    if (!f) { seterr(err, "无法打开 deb: %s", archive); return -1; }
    char magic[8];
    if (fread(magic, 1, 8, f) != 8 || memcmp(magic, "!<arch>\n", 8) != 0) {
        fclose(f);
        seterr(err, "不是 ar/deb 格式");
        return -1;
    }
    char tmpdir[600];
    snprintf(tmpdir, sizeof(tmpdir), "%s/../.gm_tmp", destDir);
    mkdir_p(tmpdir);

    int rc = -1;
    while (1) {
        char hdr[60];
        if (fread(hdr, 1, 60, f) != 60) break;
        char name[17] = {0};
        memcpy(name, hdr, 16);
        for (int i = 15; i >= 0 && name[i] == ' '; i--) name[i] = 0;
        long long size = atoll(hdr + 48);

        if (strncmp(name, "data.tar", 8) == 0) {
            char out[700];
            snprintf(out, sizeof(out), "%s/data.tar%s", tmpdir,
                     strstr(name, ".gz") ? ".gz" : (strstr(name, ".xz") ? ".xz" : ""));
            FILE *o = fopen(out, "wb");
            if (o) {
                char *buf = malloc(64 * 1024);
                long long left = size;
                while (left > 0 && buf) {
                    size_t want = (size_t)(left > 64 * 1024 ? 64 * 1024 : left);
                    size_t n = fread(buf, 1, want, f);
                    if (n == 0) break;
                    fwrite(buf, 1, n, o);
                    left -= (long long)n;
                }
                free(buf);
                fclose(o);
                if (strstr(out, ".gz")) {
                    rc = gm_tar_gz_extract(out, destDir, err);
                } else {
                    seterr(err, "暂只支持 data.tar.gz（本包为 %s）", name);
                }
                unlink(out);
            }
        } else {
            fseek(f, (long)size, SEEK_CUR);
        }
        if (size % 2) fseek(f, 1, SEEK_CUR);   /* ar 对齐 */
    }
    fclose(f);
    return rc;
}

/* ---------- SHA256 ---------- */

int gm_sha256_file(const char *path, char *out) {
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    if (!ctx) { fclose(f); return -1; }
    if (EVP_DigestInit_ex(ctx, EVP_sha256(), NULL) != 1) {
        EVP_MD_CTX_free(ctx); fclose(f); return -1;
    }
    char *buf = malloc(64 * 1024);
    if (!buf) { EVP_MD_CTX_free(ctx); fclose(f); return -1; }
    size_t n;
    while ((n = fread(buf, 1, 64 * 1024, f)) > 0) EVP_DigestUpdate(ctx, buf, n);
    free(buf);
    fclose(f);
    unsigned char md[EVP_MAX_MD_SIZE];
    unsigned int mdlen = 0;
    if (EVP_DigestFinal_ex(ctx, md, &mdlen) != 1 || mdlen != 32) {
        EVP_MD_CTX_free(ctx); return -1;
    }
    EVP_MD_CTX_free(ctx);
    for (int i = 0; i < 32; i++) sprintf(out + i * 2, "%02x", md[i]);
    out[64] = 0;
    return 0;
}

/* ---------- 下载 ---------- */

typedef struct {
    FILE *f;
    uint64_t done;
    uint64_t total;
    GMRuntimeProgressFn cb;
    void *ctx;
} DLCtx;

static int dl_body(void *ctx, const char *data, size_t len) {
    DLCtx *d = (DLCtx *)ctx;
    if (!d->f) return 0;
    fwrite(data, 1, len, d->f);
    d->done += len;
    if (d->cb) d->cb(d->done, d->total, d->ctx);
    return 0;
}

int gm_download_to_file(const char *url, const char *path,
                        GMRuntimeProgressFn cb, void *ctx, char **err) {
    // 支持多段重定向
    char cur[1024];
    snprintf(cur, sizeof(cur), "%s", url);
    for (int hop = 0; hop < 5; hop++) {
        FILE *f = fopen(path, "wb");
        if (!f) { seterr(err, "无法写入 %s", path); return -1; }
        DLCtx d = { f, 0, 0, cb, ctx };

        GMHttpReq req;
        memset(&req, 0, sizeof(req));
        req.method = "GET";
        req.url = cur;
        req.extra_headers = "Accept: */*\r\n";
        req.timeout_sec = 600;

        GMHttpResp resp;
        int rc = gm_http_perform(&req, &resp, dl_body, &d);
        fclose(f);
        if (rc != 0) {
            seterr(err, "下载失败: %s", resp.error);
            return -1;
        }
        if (resp.status == 301 || resp.status == 302 || resp.status == 307 || resp.status == 308) {
            /* 从响应头取 Location */
            const char *loc = resp.headers ? strstr(resp.headers, "ocation:") : NULL;
            if (loc) {
                loc += 9;
                while (*loc == ' ') loc++;
                const char *end = strstr(loc, "\r");
                size_t n = end ? (size_t)(end - loc) : strlen(loc);
                char next[1024];
                if (n >= sizeof(next)) n = sizeof(next) - 1;
                memcpy(next, loc, n);
                next[n] = 0;
                if (strncmp(next, "http", 4) == 0) {
                    snprintf(cur, sizeof(cur), "%s", next);
                    continue;
                }
            }
        }
        if (resp.status >= 400) {
            seterr(err, "下载失败: HTTP %d", resp.status);
            return -1;
        }
        return 0;
    }
    seterr(err, "重定向过多");
    return -1;
}

/* ---------- 一步安装 ---------- */

int gm_runtime_install(const char *url, const char *sha256, const char *destDir,
                       GMRuntimeProgressFn cb, void *ctx, char **err) {
    char tmppath[700];
    snprintf(tmppath, sizeof(tmppath), "%s.gmdownload", destDir);
    mkdir_p(destDir);

    fprintf(stderr, "[gm] download %s\n", url);
    if (gm_download_to_file(url, tmppath, cb, ctx, err) != 0) return -1;

    if (sha256 && strlen(sha256) == 64) {
        char got[65];
        if (gm_sha256_file(tmppath, got) != 0) {
            seterr(err, "无法计算校验和");
            unlink(tmppath);
            return -1;
        }
        if (strcasecmp(got, sha256) != 0) {
            seterr(err, "SHA256 校验失败\n期望 %s\n实际 %s", sha256, got);
            unlink(tmppath);
            return -1;
        }
        fprintf(stderr, "[gm] sha256 ok\n");
    }

    int rc;
    if (strstr(url, ".deb")) {
        rc = gm_deb_extract(tmppath, destDir, err);
    } else {
        rc = gm_tar_gz_extract(tmppath, destDir, err);
    }
    unlink(tmppath);
    return rc;
}
