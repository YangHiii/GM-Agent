/* GM Agent · HTTPS 传输实现（OpenSSL + getaddrinfo，chunked 解码，SSE 友好） */
#include "http.h"
#include "gm_engine.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <unistd.h>
#include <unistd.h>
#include <netdb.h>
#include <sys/socket.h>
#include <poll.h>
#include <time.h>
#include <sys/time.h>
#include <openssl/ssl.h>
#include <openssl/err.h>

static char *ci_strstr(const char *hay, const char *needle) {
    size_t nl = strlen(needle);
    for (const char *p = hay; *p; p++) {
        size_t i = 0;
        while (i < nl && p[i] && tolower((unsigned char)p[i]) == tolower((unsigned char)needle[i])) i++;
        if (i == nl) return (char *)p;
    }
    return NULL;
}

static SSL_CTX *g_ctx = NULL;

static SSL_CTX *ctx_get(void) {
    if (g_ctx) return g_ctx;
    /* OpenSSL 3.x：库初始化与错误字符串均为自动，无需手动调用 */
    g_ctx = SSL_CTX_new(TLS_client_method());
    if (!g_ctx) return NULL;
    SSL_CTX_set_min_proto_version(g_ctx, TLS1_2_VERSION);

    /* iOS 没有系统 CA 路径：优先加载随包 cacert.pem（PEM 束），
       其次是环境变量指定的路径，最后才退回默认路径。 */
    int loaded = 0;
    char cand[1024];
    const char *env = getenv("GM_CA_FILE");
    if (env && *env) loaded = SSL_CTX_load_verify_locations(g_ctx, env, NULL) == 1;
    if (!loaded) {
        const char *names[] = { "cacert.pem", "cacert.cer", NULL };
        /* 通过可执行路径推断 bundle 目录 */
        char exe[1024];
        ssize_t n = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
        if (n > 0) exe[n] = 0; else exe[0] = 0;
        char dir[1024];
        if (exe[0]) {
            snprintf(dir, sizeof(dir), "%s", exe);
            char *slash = strrchr(dir, '/');
            if (slash) *slash = 0;
        } else {
            snprintf(dir, sizeof(dir), ".");
        }
        for (int i = 0; names[i] && !loaded; i++) {
            snprintf(cand, sizeof(cand), "%s/%s", dir, names[i]);
            if (access(cand, R_OK) == 0) {
                loaded = SSL_CTX_load_verify_locations(g_ctx, cand, NULL) == 1;
                fprintf(stderr, "[gm] CA: %s -> %s\n", cand, loaded ? "ok" : "fail");
            }
        }
    }
    if (!loaded) {
        /* 退路：默认路径 + 系统钥匙串（macOS/iOS 上的 ld-musl 不会有） */
        SSL_CTX_set_default_verify_paths(g_ctx);
        fprintf(stderr, "[gm] CA: 未找到 cacert.pem，使用默认路径（iOS 上大概率失败）\n");
    }
    SSL_CTX_set_verify(g_ctx, SSL_VERIFY_PEER, NULL);
    return g_ctx;
}

static int parse_url(const char *url, char *host, size_t hcap,
                     char *port, size_t pcap, char *path, size_t pacp) {
    const char *p = url;
    int tls = 1;
    if (strncmp(p, "https://", 8) == 0) { p += 8; tls = 1; }
    else if (strncmp(p, "http://", 7) == 0) { p += 7; tls = 0; }
    else return -1;
    const char *slash = strchr(p, '/');
    const char *hostend = slash ? slash : p + strlen(p);
    const char *colon = memchr(p, ':', (size_t)(hostend - p));
    size_t hl = (size_t)((colon ? colon : hostend) - p);
    if (hl == 0 || hl >= hcap) return -1;
    memcpy(host, p, hl);
    host[hl] = 0;
    if (colon) {
        size_t pl = (size_t)(hostend - colon - 1);
        if (pl >= pcap) return -1;
        memcpy(port, colon + 1, pl);
        port[pl] = 0;
    } else {
        snprintf(port, pcap, "%s", tls ? "443" : "80");
    }
    snprintf(path, pacp, "%s", (slash && slash[1]) ? slash : "/");
    return tls;
}

static int tcp_connect(const char *host, const char *port, int timeout_sec, char *err, size_t errcap) {
    struct addrinfo hints, *res = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = (strcmp(host, "127.0.0.1") == 0 || strcmp(host, "localhost") == 0)
                      ? AF_INET : AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    int rc = getaddrinfo(host, port, &hints, &res);
    if (rc != 0) {
        snprintf(err, errcap, "域名解析失败(%s)：请检查网关地址是否完整，需形如 https://api.openai.com/v1/chat/completions  原始错误: %s", host, gai_strerror(rc));
        return -1;
    }
    int fd = -1;
    for (struct addrinfo *ai = res; ai; ai = ai->ai_next) {
        fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0) continue;
        struct timeval tv = { timeout_sec, 0 };
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
        if (connect(fd, ai->ai_addr, ai->ai_addrlen) == 0) break;
        close(fd);
        fd = -1;
    }
    freeaddrinfo(res);
    if (fd < 0) snprintf(err, errcap, "TCP 连接失败: %s", host);
    return fd;
}

static int write_all(SSL *ssl, int fd, const char *data, size_t len) {
    size_t off = 0;
    while (off < len) {
        int n = ssl ? SSL_write(ssl, data + off, (int)(len - off))
                    : (int)write(fd, data + off, len - off);
        if (n <= 0) return -1;
        off += (size_t)n;
    }
    return 0;
}

static int read_some(SSL *ssl, int fd, char *buf, size_t cap);

/* 带空闲超时的读取：无数据超过 idle_ms 返回 -2（超时） */
static int read_some_idle(SSL *ssl, int fd, char *buf, size_t cap, int idle_ms) {
    int waited = 0;
    for (;;) {
        struct pollfd pfd = { fd, POLLIN, 0 };
        int pr = poll(&pfd, 1, 200);
        if (pr > 0) break;
        if (pr < 0) return -1;
        waited += 200;
        if (waited >= idle_ms) return -2;
        /* 优先消耗 SSL 内部已解密数据 */
        if (ssl && SSL_pending(ssl) > 0) break;
    }
    return read_some(ssl, fd, buf, cap);
}

static int read_some(SSL *ssl, int fd, char *buf, size_t cap) {
    if (ssl) {
        int n = SSL_read(ssl, buf, (int)cap);
        if (n > 0) return n;
        int e = SSL_get_error(ssl, n);
        if (e == SSL_ERROR_ZERO_RETURN) return 0;
        if (e == SSL_ERROR_SYSCALL && n == 0) return 0;
        return -1;
    }
    ssize_t n = read(fd, buf, cap);
    return (int)n;
}

int gm_http_resp_status(const void *resp) {
    if (!resp) return 0;
    const GMHttpResp *r = (const GMHttpResp *)resp;
    return r->status;
}

int gm_http_perform(const GMHttpReq *req, GMHttpResp *resp, GMHttpBodyFn on_body, void *ctx) {
    memset(resp, 0, sizeof(*resp));
    resp->status = 0;
    resp->content_length = -1;

    char host[256], port[8], path[2048];
    int tls = parse_url(req->url, host, sizeof(host), port, sizeof(port), path, sizeof(path));
    if (tls < 0) { snprintf(resp->error, sizeof(resp->error), "URL 无效"); return -1; }
    if (strstr(req->url, "://") && strncmp(req->url, "https://", 8) != 0) tls = 0;

    int timeout = req->timeout_sec > 0 ? req->timeout_sec : 120;
    int fd = tcp_connect(host, port, timeout, resp->error, sizeof(resp->error));
    if (fd < 0) return -1;

    SSL *ssl = NULL;
    if (tls) {
        SSL_CTX *c = ctx_get();
        if (!c) { close(fd); snprintf(resp->error, sizeof(resp->error), "TLS 初始化失败"); return -1; }
        ssl = SSL_new(c);
        SSL_set_fd(ssl, fd);
        SSL_set_tlsext_host_name(ssl, host);
        SSL_set1_host(ssl, host);
        if (SSL_connect(ssl) != 1) {
            snprintf(resp->error, sizeof(resp->error), "TLS 握手失败: %s",
                     ERR_error_string(ERR_get_error(), NULL));
            SSL_free(ssl);
            close(fd);
            return -1;
        }
    }

    /* 拼请求 */
    char reqbuf[8192];
    int n = snprintf(reqbuf, sizeof(reqbuf),
                     "%s %s HTTP/1.1\r\nHost: %s\r\nUser-Agent: gm-agent/%s\r\n"
                     "Accept: application/json, text/event-stream\r\nConnection: close\r\n",
                     req->method ? req->method : "GET", path, host, "0.1.0");
    if (req->bearer && req->bearer[0]) {
        n += snprintf(reqbuf + n, sizeof(reqbuf) - n, "Authorization: Bearer %s\r\n", req->bearer);
    }
    if (req->extra_headers) {
        n += snprintf(reqbuf + n, sizeof(reqbuf) - n, "%s", req->extra_headers);
    }
    if (req->body && req->body_len) {
        n += snprintf(reqbuf + n, sizeof(reqbuf) - n,
                      "Content-Type: application/json\r\nContent-Length: %zu\r\n", req->body_len);
    }
    n += snprintf(reqbuf + n, sizeof(reqbuf) - n, "\r\n");
    if (write_all(ssl, fd, reqbuf, (size_t)n) != 0 ||
        (req->body && req->body_len && write_all(ssl, fd, req->body, req->body_len) != 0)) {
        snprintf(resp->error, sizeof(resp->error), "写请求失败");
        if (ssl) SSL_free(ssl);
        close(fd);
        return -1;
    }

    /* 读响应头 */
    char *buf = malloc(65536);
    if (!buf) { if (ssl) SSL_free(ssl); close(fd); return -1; }
    size_t blen = 0;
    ssize_t hdr_end = -1;
    while (hdr_end < 0) {
        int r = read_some(ssl, fd, buf + blen, 65536 - blen - 1);
        if (r <= 0) { snprintf(resp->error, sizeof(resp->error), "读响应头失败"); free(buf); if (ssl) SSL_free(ssl); close(fd); return -1; }
        blen += (size_t)r;
        buf[blen] = 0;
        char *p = strstr(buf, "\r\n\r\n");
        if (p) hdr_end = (p - buf) + 4;
        if (blen > 60000) break;
    }
    if (hdr_end < 0) { snprintf(resp->error, sizeof(resp->error), "响应头不完整"); free(buf); if (ssl) SSL_free(ssl); close(fd); return -1; }

    resp->headers = malloc((size_t)hdr_end + 1);
    if (resp->headers) {
        memcpy(resp->headers, buf, (size_t)hdr_end);
        resp->headers[hdr_end] = 0;
    }
    int st = 0;
    if (sscanf(buf, "HTTP/%*d.%*d %d", &st) == 1) resp->status = st;
    resp->ok = 1;

    /* 总时长看门狗 */
    struct timespec t_start;
    clock_gettime(CLOCK_MONOTONIC, &t_start);
    long long deadline_ms = (long long)timeout * 1000;

    int chunked = 0;
    char *cl = ci_strstr(buf, "\r\ncontent-length:");
    if (cl) resp->content_length = atoll(cl + 17);
    if (ci_strstr(buf, "\r\ntransfer-encoding: chunked")) chunked = 1;

    /* body */
    size_t consumed = (size_t)hdr_end;
    size_t body_avail = blen - consumed;
    if (chunked) {
        /* 增量 chunked 解码状态机 */
        char *cbuf = malloc(65536);
        size_t cb_len = 0;
        if (!cbuf) { free(buf); if (ssl) SSL_free(ssl); close(fd); return -1; }
        int state = 0;             /* 0=等长度行 1=chunk 数据 2=等 CRLF 3=done */
        size_t remain = 0;
        for (;;) {
            /* 先把已有数据并入 cbuf，再处理 */
            if (body_avail) {
                if (cb_len + body_avail > 65536) body_avail = 65536 - cb_len;
                memcpy(cbuf + cb_len, buf + consumed, body_avail);
                cb_len += body_avail;
            }
            consumed = blen;
            body_avail = 0;
            size_t pos = 0;
            int progress = 1;
            while (progress && pos < cb_len) {
                progress = 0;
                if (state == 0) {
                    char *nl = memchr(cbuf + pos, '\n', cb_len - pos);
                    if (!nl) break;
                    size_t hl = (size_t)(nl - (cbuf + pos));
                    if (hl && cbuf[pos + hl - 1] == '\r') hl--;
                    remain = strtoul(cbuf + pos, NULL, 16);
                    pos += (size_t)(nl - (cbuf + pos)) + 1;
                    state = remain ? 1 : 3;
                    progress = 1;
                } else if (state == 1) {
                    size_t avail = cb_len - pos;
                    size_t take = remain < avail ? remain : avail;
                    if (take && on_body && on_body(ctx, cbuf + pos, take) != 0) {
                        free(cbuf);
                        free(buf);
                        if (ssl) { SSL_shutdown(ssl); SSL_free(ssl); }
                        close(fd);
                        return 0;
                    }
                    pos += take;
                    remain -= take;
                    if (remain == 0) state = 2;
                    progress = 1;
                } else if (state == 2) {
                    /* chunk 数据后必须完整消费 "\r\n" 才能回到长度行。
                       若两个字节被拆到不同 TCP 包，必须保持 state=2 等下一包，
                       否则单独的 '\n' 会被当成 "size=0" 导致流提前结束。 */
                    if (pos < cb_len && cbuf[pos] == '\r') {
                        pos++;
                        if (pos < cb_len) {
                            if (cbuf[pos] == '\n') pos++;
                            state = 0;
                            progress = 1;
                        } else {
                            break;   /* 等 '\n' */
                        }
                    } else if (pos < cb_len && cbuf[pos] == '\n') {
                        pos++;
                        state = 0;
                        progress = 1;
                    } else {
                        break;       /* 一个字节都没到 */
                    }
                } else break;
            }
            if (pos) {
                memmove(cbuf, cbuf + pos, cb_len - pos);
                cb_len -= pos;
            }
            if (state == 3) break;
            struct timespec now2;
            clock_gettime(CLOCK_MONOTONIC, &now2);
            long long elapsed = (now2.tv_sec - t_start.tv_sec) * 1000LL +
                                (now2.tv_nsec - t_start.tv_nsec) / 1000000;
            if (elapsed > deadline_ms) { gm_logf("请求总时长超过 %d 秒，强制结束", timeout); break; }

            int r = read_some_idle(ssl, fd, buf, 65536 - 1, 45000);
            if (r == -2) { gm_logf("SSE 空闲 45 秒，主动结束"); break; }
            if (r <= 0) break;
            blen = (size_t)r;
            consumed = 0;
            body_avail = blen;
        }
        free(cbuf);
    } else {
        if (body_avail && on_body && on_body(ctx, buf + consumed, body_avail) != 0) {
            if (ssl) { SSL_shutdown(ssl); SSL_free(ssl); ssl = NULL; }
            close(fd);
            free(buf);
            return 0;
        }
        for (;;) {
            int r = read_some_idle(ssl, fd, buf, 65536 - 1, 45000);
            if (r == -2) { gm_logf("响应空闲 45 秒，主动结束"); break; }
            if (r <= 0) break;
            if (on_body && on_body(ctx, buf, (size_t)r) != 0) break;
        }
    }

    free(buf);
    if (ssl) { SSL_shutdown(ssl); SSL_free(ssl); }
    close(fd);
    return 0;
}
