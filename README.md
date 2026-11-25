# GM Agent

自研 iOS Agent 客户端（闭源开发）。ObjC 原生 UI + 独立 arm64 引擎子进程，不依赖任何第三方成品包的二进制或授权服务。

## 架构

```
GMAgent.app (ObjC)
 ├─ UI     GMChatViewController / GMSettingsViewController
 └─ Bridge GMBridge ── posix_spawn + pipe ──▶ gm-engine
                                                 │
                                                 ├─ provider.c  OpenAI 兼容 SSE 流式
                                                 ├─ tool.c      /bin/sh 工具执行（超时/截断）
                                                 ├─ turn.c      工具循环（≤8 轮）
                                                 └─ session.c   JSONL 会话落盘
```

引擎自包含 TLS（OpenSSL 静态链接），单进程闭环，stdio 上跑 NDJSON JSON-RPC。

## 目录

| 路径 | 说明 |
|---|---|
| `engine/` | C99 引擎，产出 `gm-engine` |
| `app/` | iOS ObjC 应用（无 Swift） |
| `docs/ARCHITECTURE.md` | 架构与进程模型 |
| `docs/PROTOCOL.md` | 自研协议 `gm-1` |
| `docs/codex-protocol.md` | 调研笔记：OpenAI Codex app-server 协议（带源码行号） |
| `scripts/test_engine.sh` | 离线回归（含 mock 提供方端到端） |
| `scripts/mock_provider.py` | 本地模拟 SSE 提供方 |
| `.github/workflows/build-ipa.yml` | CI：Linux 跑测试 → macOS 出 ipa |

## 本地开发（Linux / iSH / macOS）

```sh
apk add gcc musl-dev openssl-dev        # 或 apt install build-essential libssl-dev
sh scripts/test_engine.sh               # 编译 + 协议回归 + 端到端
```

手动跑一轮对话：

```sh
cc -std=gnu99 -O2 -Iengine -o gm-engine engine/*.c -lssl -lcrypto
printf '{"id":1,"method":"gm/thread/start"}\n{"id":2,"method":"gm/turn/start","params":{"text":"跑一下 echo hi"}}\n' \
  | GM_BASE_URL=http://127.0.0.1:8771/v1/chat/completions GM_API_KEY=xxx ./gm-engine --mode app-server
```

## 构建 ipa

推送到 `main` 后 GitHub Actions 自动构建，产物在 Actions → run → Artifacts → `GMAgent-ipa`。
打 `v*` tag 会额外附到 Release。

首次构建会交叉编译 OpenSSL（约 8 分钟），之后走 cache。

## 安装

- **TrollStore**：直接安装 artifact 里的 `.ipa`（ad-hoc 签名即可）
- **AltStore / Sideloadly**：用你自己的开发者证书重签；如需完整沙箱权限，把
  `app/Resources/entitlements.plist` 换成平台级 entitlement（仅 TrollStore 可用）

## 配置

首次启动 → 右上「设置」：

| 项 | 说明 |
|---|---|
| 网关 | OpenAI 兼容的 `/v1/chat/completions` 地址 |
| 模型 | slug，如 `gpt-5.2`（后续接入 `model/list` 动态获取） |
| 推理强度 | low / medium / high |
| API Key | 存 iOS Keychain |

## 协议

`gm-1`：`initialize` / `thread/start` / `turn/start` / `tool/shell` + 事件 `gm/event/{delta,toolCall,toolResult,turnEnd,error}`。
详见 `docs/PROTOCOL.md`。后续会增加 `--protocol codex` 兼容模式（对齐官方 app-server 语义）。

## 许可

闭源。版权所有。
