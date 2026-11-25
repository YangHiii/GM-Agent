GM Agent · 引擎（gm-engine）
====================

## 状态：可运行骨架（2026-11-26）

在本机（iSH aarch64 Alpine）用 `cc -std=gnu99` 编译通过并跑通 JSON-RPC 往返：

```
$ printf '{"id":1,"method":"gm/initialize"}\n{"id":2,"method":"gm/thread/start"}\n{"id":3,"method":"gm/ping"}\n' | ./gm-engine --mode app-server
{"jsonrpc":"2.0","id":1,"result":{"version":"0.1.0","protocol":"gm-1"}}
{"jsonrpc":"2.0","id":2,"result":{"thread":{"id":"gm-1795637010"}}}
{"jsonrpc":"2.0","id":3,"result":"pong"}
```

已实现：`gm/initialize`、`gm/thread/start`、`gm/ping`。
待实现：`gm/turn/start`（含 provider 流式调用 + 工具循环）、`gm/turn/cancel`、事件通知。

## 文件

| 文件 | 作用 | 状态 |
|---|---|---|
| `gm_engine.h` | 公共类型：GMBuf、GMPVal（JSON DOM）、GMSession、GMProvider | 完成 |
| `json.c` | JSON 解析器 + 序列化器（零依赖，DOM，UTF-8/\\u 转义） | 完成，单测通过 |
| `session.c` | 会话历史（内存 + `~/.gm/sessions/<id>.jsonl` 追加） | 完成 |
| `tool.c` | `gm_tool_run_shell`（fork/exec `/bin/sh -c`，pipe 收输出，超时 SIGKILL） | 完成，待接主循环 |
| `tool.c: gm_tool_specs` | OpenAI 兼容 tools 声明（`shell` 函数） | 完成 |
| `main.c` | stdio JSON-RPC 主循环 | 骨架 |
| `provider.c` | HTTPS + SSE 流式（OpenAI Chat Completions 兼容） | **待写** |

## 本机编译

```sh
apk add gcc musl-dev openssl-dev
cc -std=gnu99 -O2 -o gm-engine engine/json.c engine/session.c engine/tool.c engine/main.c
```

## 已知本机限制（重要）

1. **iSH 的 free() 在 double-free 时会直接 SIGSEGV**（无诊断信息）。主循环里所有 `GMPVal*` 的所有权必须显式转移，禁止「同一个指针既放进容器又被单独 free」。已在 main.c 用 `id` 深拷贝规避。
2. 编译用 `-std=gnu99`（`strdup`/`strsrnlen` 等 POSIX 函数在 `-std=c99` 下不声明）。
3 . 本机无 macOS SDK，**iOS arm64 目标由 GitHub Actions（macos-14）产出**，见 `.github/workflows/build-ipa.yml`。

## 下一步（按优先级）

1. `engine/provider.c`：OpenAI 兼容协议的 SSE 流式客户端（libcurl 或裸 TLS + 手写 SSE 解析），产出 `on_delta(kind, text)` 与 `on_tool(id, name, args)` 回调。
2. `gm/turn/start`：拼 messages（system prompt + history + user）→ provider 流式 → 若有 tool_call 则 `gm_tool_run_shell` → 回填 tool 结果 → 再请求，最多 N 轮。
3. 事件推送：`gm/event/delta`、`gm/event/toolCall`、`gm/event/toolResult`、`gm/event/turnEnd`（App 侧 `GMConversation.m` 已按此解析）。
4. 单元测试：`scripts/test_engine.sh` 跑一遍离线协议往返（不需要网络）。
5. App 侧补齐：模型/供应商设置页、会话列表、工具卡片折叠、审批弹窗。

## 与原版（CodexApp）的差异

- 不 fork 子进程做 Codex CLI 的 RPC 转发，**引擎自己就是 RPC 服务端**。
- 工具直接 `/bin/sh`，不维护 47 个 `ca-filetool` 符号链接。
- 无 service360 / 设备 UUID / 签名策略；授权可选，走 Ed25519 本地离线校验。
