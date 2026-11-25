# GM Agent · 架构（闭源复刻）

目标：不依赖 MT/CodexApp 任何二进制、不依赖 service360 授权链，产出可自持的 iOS Agent 客户端。
原产品功能域（从 216 个类、4 010 条文案、59 个 CA 导出符号归纳）：

| 域 | 原实现要点 | 复刻策略 |
|---|---|---|
| 会话界面 | ObjC UIKit，纯代码布局，216 类 | UIKit + 自研 `GMChatViewController`（列表 + 输入栏 + 工具卡片） |
| Agent 引擎 | 独立子进程 `codex app-server`，stdio JSON-RPC，流式事件 | 自研 `gm-engine`（C/ObjC，静态链接），同样的 JSON-RPC over stdio |
| 工具执行 | Helpers/ 全是 `ca-filetool` 符号链接（cat/ls/grep/sed…）+ bash trampoline | 直接派 `/bin/sh -c`（TrollStore 无沙箱），不做多调用替换 |
| 文件工具 | `CAFileToolMain` 通过 `argv[0]` 分发 | 单二进制 `gm-tool` + argv[0] 分发 |
| 模型网关 | OpenAI / OpenRouter / 第三方 baseURL + API Key；ChatGPT OAuth | 统一 `GMProvider` 抽象：OpenAI 兼容 / Anthropic / 自定义 |
| Runtime 管理 | 从 GitHub 拉 codex runtime manifest + 签名 | 不需要（引擎内置），仅保留可选的运行时组件更新 |
| 构建环境 | Theos/CMake/Ninja 内嵌，`codex-sign` 签名 | 复用同一套思路：内置 `clang` wrapper + `ldid` 等价签名器 |
| 分享/相册/语音 | ShareExtension + PhotosUI + AVFAudio | ShareExtension + PhotosUI + Speech 框架 |
| 授权 | service360 + 设备 UUID + 签名策略 | **无**：本地 license 只有自签 Ed25519，可离线校验（可选） |

## 进程模型

```
GM App (ObjC)
 ├─ UI 线程 ── GMChatViewController
 └─ AgentBridge ── fork/exec ── gm-engine (stdio JSON-RPC 双向)
                                 ├─ tool execution → /bin/sh -c
                                 ├─ provider client (HTTP/2 via libcurl)
                                 └─ session store (SQLite)
```

## JSON-RPC 协议（gm-engine）

严格对齐 Codex app-server 的方法语义，但 method 名统一前缀 `gm/`，避免与原版混淆：

- `gm/initialize` → `{clientInfo, capabilities}`
- `gm/thread/start`, `gm/thread/list`, `gm/thread/resume`
- `gm/turn/start`（user input + model + effort）
- 通知：`gm/event/delta`（`text` / `reasoning` / `tool_call` / `tool_result` / `usage`）、`gm/event/turnEnd`
- `gm/approval/request` / `gm/approval/respond`（命令审批）

详见 `docs/PROTOCOL.md`（由协议调研补全）。

## 目录

```
app/            iOS 目标：UI + 桥接（ObjC，无 Swift，保持与原地一致以降低体积）
engine/         gm-engine 源码（C99 + 少量 ObjC），产出 arm64 静态可执行
third_party/    libcurl / json / sqlite3 / ldid 等价实现
scripts/        交叉编译、打包、签名脚本
docs/           架构 / 协议 / 构建说明
```

## 构建链（关键约束）

本机（iSH aarch64 Alpine）无 Xcode、无 clang 交叉链。两条路：

1. **GitHub Actions 构建**（推荐）：workflow 用 `macos-14`（自带 Xcode + iOS SDK）编译出 arm64 Mach-O、ad-hoc 签名、产出 ipa artifact；本地只需 `git push`。
2. **本地交叉链**：`third_party/cctools` + iOS SDK（需自行提供），或 `zig cc -target aarch64-macos`（不能产出 iOS Mach-O，仅可用于 engine 的单测）。

CI 是唯一能稳定出 iOS 二进制的环境，仓库即构建产物来源。
