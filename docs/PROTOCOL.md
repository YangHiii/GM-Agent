# GM Agent · 协议（gm-1）

传输：stdio，每行一个 JSON 对象（JSON-RPC 2.0 风格）。二进制：`gm-engine --mode app-server`。

## 客户端 → 引擎

| method | params | 返回 |
|---|---|---|
| `gm/initialize` | `{}` | `{version, protocol, model, configured}` |
| `gm/thread/start` | `{}` | `{thread:{id}}` |
| `gm/turn/start` | `{text}` | `true`（立即返回，后续走事件） |
| `gm/turn/cancel` | `{threadId}` | `true` |
| `gm/tool/shell` | `{command, cwd?}` | `{output, code}` |
| `gm/tools/list` | `{}` | OpenAI 兼容 tools 数组 |
| `gm/config` | `{baseURL?, apiKey?, model?}` | `true` |

## 引擎 → 客户端（通知，无 id）

| method | params |
|---|---|
| `gm/event/delta` | `{kind: "text"｜"reasoning", delta}` |
| `gm/event/toolCall` | `{id, name, summary}` |
| `gm/event/toolResult` | `{id, output, code}` |
| `gm/event/turnEnd` | `{finish, inputTokens, outputTokens}` |
| `gm/event/error` | `{message}` |

## 一次完整回合（实测输出）

```
→ {"id":1,"method":"gm/thread/start"}
← {"jsonrpc":"2.0","id":1,"result":{"thread":{"id":"gm-1795637568-1"}}}
→ {"id":2,"method":"gm/turn/start","params":{"text":"跑一下 echo"}}
← {"jsonrpc":"2.0","id":2,"result":true}
← {"method":"gm/event/delta","params":{"kind":"text","delta":"我先"}}
← {"method":"gm/event/delta","params":{"kind":"text","delta":"跑一下"}}
← {"method":"gm/event/delta","params":{"kind":"text","delta":"命令"}}
← {"method":"gm/event/toolCall","params":{"id":"call_1","name":"shell","summary":"{\"command\": \"echo gm-alive\"}"}}
← {"method":"gm/event/toolResult","params":{"id":"call_1","output":"gm-alive\n","code":0}}
← {"method":"gm/event/delta","params":{"kind":"text","delta":"命令输出是: gm-alive"}}
← {"method":"gm/event/turnEnd","params":{"finish":"stop","inputTokens":12,"outputTokens":7}}
```

## 提供方协议（engine → LLM）

标准 OpenAI Chat Completions，`stream: true`，SSE：

- 文本增量：`choices[0].delta.content`
- 推理增量：`choices[0].delta.reasoning_content` 或 `reasoning`
- 工具调用增量：`choices[0].delta.tool_calls[i]`（按 `index` 聚合 `id`/`function.name`/`function.arguments` 分片）
- 结束：`data: [DONE]`；用量：`usage.prompt_tokens` / `usage.completion_tokens`

配置来源（优先级）：`gm/config` 消息 > 环境变量 `GM_BASE_URL` / `GM_API_KEY` / `GM_MODEL`。

## 工具循环

最多 8 轮。每轮：请求 → 收增量 → 若有 `tool_calls` 则执行 `shell`，把结果以 `role:"tool"` 回填 messages，再请求；无工具调用则 `turnEnd`。

## 内存模型（实现约束）

- 主 arena（16 MB）：一条消息一个生命周期。
- 回合 arena：整个 turn。**事件对象必须挂在回合的 outArena**，不能被 g_out 回退冲掉（这是本机踩过的坑）。
- 工具参数解析用独立 256 KB arena，用完立即释放。
- 工具输出是唯一走 `malloc/free` 的临时值。
