# 安装与首启验证

## 1. 拿到 ipa

CodeMagic → 构建页 → **Artifacts** → 下载 `GMAgent.ipa`（约 12-15 MB）。

## 2. 装到 iPhone

| 方式 | 前提 | 步骤 |
|---|---|---|
| **TrollStore**（推荐） | 设备已装 TrollStore | 把 ipa 传到手机 → 文件 App 里点开 → 用 TrollStore 打开 → Install |
| **AltStore / Sideloadly** | 有 Apple ID | Sideloadly：连数据线 → 拖入 ipa → 填 Apple ID → Start。7 天后需重签 |
| **Xcode** | 有 Mac | `xcrun devicectl device install app --device <UDID> build/GMAgent.app` |

> ad-hoc 签名（`codesign --sign -`）只能被 TrollStore 或已越狱设备直接安装；普通设备必须重签。

## 3. 首启验证清单

打开 App 后按顺序检查，任一步失败把现象记下来。

### ① 能否启动
- 预期：进入「GM Agent」聊天页，标题栏左「新会话」右「设置」
- 失败：闪退 → 看 Xcode Console 或 `idevicesyslog | grep GM`

### ② 设置页
- 点右上「设置」
- 填三项：网关、模型、API Key
- 网关示例：`https://api.openai.com/v1/chat/completions`
- 模型示例：`gpt-5.2`
- 点「保存」→ 应回到聊天页

### ③ 引擎是否起来了
- 在聊天页随便发一句「hi」
- 如果弹出「引擎已退出（-1）」或「gm-engine 未随包发布」→ 引擎没起来，看下一条

检查引擎是否存在：
```sh
# TrollStore 装的 app 在 /var/containers/Bundle/Application/<UUID>/GMAgent.app/
ls -la /var/containers/Bundle/Application/*/GMAgent.app/gm-engine
```
应该存在且可执行（`-rwxr-xr-x`）。

### ④ 一次完整对话
- 发「用 shell 执行 echo gm-alive 然后告诉我输出」
- 预期：
  1. 出现「GM Agent · 生成中…」
  2. 文本流式增长
  3. 出现「工具 · shell」卡片，内容含 `{"command": "echo gm-alive"}`
  4. 出现工具结果 `gm-alive`
  5. 最终回答含「gm-alive」

### ⑤ 工具执行是否真在本机跑
- 发「在 /tmp 建一个文件 gm-test.txt，内容是 hello」
- 预期：工具卡片显示 `code: 0`
- 到文件 App 或 ssh 上确认 `/tmp/gm-test.txt` 存在

## 4. 常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| `引擎已退出（-1）` | 引擎二进制缺失或架构不对 | `file gm-engine` 应显示 `Mach-O 64-bit executable arm64` |
| `HTTP 401` | API Key 无效 | 换 key；确认网关地址正确 |
| `TCP 连接失败` | 网络或 DNS | 换网络；确认设备能访问该域名 |
| 工具卡片显示 `code: 127` | 命令不存在 | 当前是精简环境，`sh` 路径 `/bin/sh` 可能在沙箱下不可用 |
| 设置保存后无效 | Keychain 写入失败 | 检查 entitlements 是否含 `keychain-access-groups` |
