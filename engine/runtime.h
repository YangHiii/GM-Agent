/* GM Agent · 运行时安装器
 * 支持 .tar.gz 与 .deb（ar + data.tar.gz）
 * 依赖：zlib（gzOpen 流式解压）+ OpenSSL（SHA256）
 */
#ifndef GM_RUNTIME_H
#define GM_RUNTIME_H

#include "gm_engine.h"

/* 解压 tar.gz 到 destDir。返回 0 成功；err 输出错误描述（malloc） */
int gm_tar_gz_extract(const char *archive, const char *destDir, char **err);

/* 解压 .deb（ar 容器）到 destDir */
int gm_deb_extract(const char *archive, const char *destDir, char **err);

/* 计算文件 SHA256，hex 写入 out（65 字节） */
int gm_sha256_file(const char *path, char *out);

/* 下载 url 到 path；on_progress(done, total) 可为 NULL */
typedef void (*GMRuntimeProgressFn)(uint64_t done, uint64_t total, void *ctx);
int gm_download_to_file(const char *url, const char *path,
                        GMRuntimeProgressFn cb, void *ctx,
                        char **err);

/* 一步安装：下载 → 校验 → 解压 → 结果目录 */
int gm_runtime_install(const char *url, const char *sha256, const char *destDir,
                       GMRuntimeProgressFn cb, void *ctx, char **err);

/* 扩展：支持大小校验与跳过 SHA256 */
int gm_runtime_install_ex(const char *url, const char *sha256, const char *destDir,
                          long long expect_size, int skip_verify,
                          GMRuntimeProgressFn cb, void *ctx, char **err);

#endif
