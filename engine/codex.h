/* GM Agent · Codex 运行时集成
 *
 * 启动已安装的 codex app-server 子进程，用 NDJSON 协议通信，
 * 把 Codex 的 item/* 通知转成本引擎的 gm/event/* 事件。
 * 这样 UI 层完全不用改，只是引擎内部换成真正的 Codex。
 */
#ifndef GM_CODEX_H
#define GM_CODEX_H

#include "gm_engine.h"

/* 递归查找 codex 可执行文件；返回 malloc 的路径，未找到返回 NULL */
char *gm_codex_find_binary(void);

/* 是否可用（二进制存在） */
int gm_codex_available(void);

/* 启动并握手；成功返回 0 */
int gm_codex_start(char **err);

/* 停止 */
void gm_codex_stop(void);

/* 是否已就绪 */
int gm_codex_ready(void);

/* 开新线程，返回 threadId（malloc） */
char *gm_codex_thread_start(char **err);

/* 发送一轮对话；事件通过 gm_emit 推送 */
int gm_codex_turn(const char *thread_id, const char *text, char **err);

/* 中断当前回合 */
void gm_codex_interrupt(void);

/* 写入/读取 codex 的 config.toml（用当前 provider 配置） */
int gm_codex_write_config(const char *base_url, const char *api_key,
                          const char *model, char **err);

#endif
