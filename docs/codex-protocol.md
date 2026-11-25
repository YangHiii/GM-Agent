# OpenAI Codex CLI `app-server` 协议与认证 — 复刻笔记 (GM Agent)

来源：openai/codex `main` 分支 tarball（codeload.github.com/openai/codex/tar.gz/refs/heads/main，2026-06 抓取）。
下文 `:N` 均指 tarball 内 `codex-main/` 前缀省略后的路径。

## 0. 传输与信封（先看这个）

- 启动：`codex app-server`，默认 `--listen stdio://`（`AppServerTransport::DEFAULT_LISTEN_URL`）
  也支持 `unix://`、`ws://IP:PORT`、`off`。`--stdio` 等价于 `--listen stdio://`。
  来源 `codex-rs/cli/src/main.rs:579-620`、`codex-rs/app-server/src/main.rs:45-50`
- **不是严格 JSON-RPC 2.0**：不发也不收 `"jsonrpc":"2.0"` 字段（`codex-rs/app-server-protocol/src/rpc.rs:1-2`）。
  一行一条 JSON（JSONL / NDJSON），framing = 换行分隔。
- 四种报文（`rpc.rs:40-85`）：
  - Request: `{"id": <int|string>, "method": "...", "params": {...}, "trace"?: {...}}`
  - Response: `{"id": ..., "result": {...}}`
  - Error: `{"error": {"code": -326xx, "message": "...", "data"?: {...}}, "id": ...}`
  - Notification: `{"method": "...", "params": {...}, "emittedAtMs"?: <unix ms>}`（无 id）
    `emittedAtMs` 由 `ServerNotificationEnvelope` 平铺注入（`protocol/common.rs:2228-2245`）
- 关闭期错误：`-32600` + `data:{"reason":"serverShuttingDown"}`；参数错误 `-32602`（`app-server/README.md`）
- 所有 struct 都是 `#[serde(rename_all = "camelCase")]` → 线上字段是 camelCase。

## A) JSON-RPC 方法表

### A1. 客户端 → 服务端 请求（`client_request_definitions!`，`protocol/common.rs:530-1950`）

| method | 关键 params | 来源 |
|---|---|---|
| `initialize` | `clientInfo{name,title,version}`, `capabilities{experimentalApi?,optOutNotificationMethods?,requiredHumanApproval?,explicitGatewayOauth?}` | `protocol/v1.rs:29-45`; common.rs:531 |
| `account/read` | `refreshToken?:bool` → `{account,authMode?,planType?,userId?,requiresOpenaiAuth}` | `v2/account.rs:610-630` |
| `account/login/start` | tag `type`: `apiKey`{apiKey} / `chatgpt`{codexStreamlinedLogin,useHostedLoginSuccessPage,appBrand} / `chatgptDeviceCode`{} / `chatgptAuthTokens`{accessToken,chatgptAccountId,chatgptPlanType} | `v2/account.rs:77-140` |
| `account/login/cancel` | `loginId` | `v2/account.rs:193` |
| `account/logout` | `{}` | common.rs |
| `account/rateLimits/read` | `{supportsLunaReserve?,excludeResetCreditDetails?}` → `{rateLimits,rateLimitsByLimitId,accountId}` | `v2/account.rs:640-660` |
| `account/usage/read` | → `{summary,dailyUsageBuckets}` | `v2/account.rs:477-500` |
| `thread/start` | `model?`, `modelProvider?`, `cwd?`, `approvalPolicy?`, `approvalsReviewer?`, `sandbox?`(read-only/workspace-write/danger-full-access), `config?`, `baseInstructions?`, `serviceTier?` | `v2/thread.rs:64-110`; common.rs:583 |
| `thread/resume` | `{threadId, history?, path?}` | `v2/thread.rs:380-400`; common.rs:589 |
| `thread/fork` | `{threadId, ...}` | common.rs:595 |
| `thread/list` | `{cursor?,limit?,sortKey?,sortDirection?,currentAccountOnly?,includedThreadIds?,excludedThreadIds?,modelProviders?}` → `{data:[Thread],nextCursor}` | `v2/thread.rs:1475-1510` |
| `thread/read` | `{threadId, includeTurns?}` | `v2/thread.rs:1832-1840` |
| `thread/turns/list` | `{threadId,cursor?,limit?}` | common.rs:941 |
| `thread/items/list` | `{threadId,cursor?,limit?}` | common.rs:948 |
| `thread/archive` / `thread/unarchive` / `thread/delete` | `{threadId}` | common.rs:614-624, 779 |
| `thread/name/set` | `{threadId,name}` | common.rs:648 |
| `thread/compact/start` | `{threadId}` (手动压缩上下文) | common.rs:784 |
| `thread/shellCommand` | `{threadId, command}` (直接跑 shell，不起模型轮次) | common.rs:789 |
| `thread/unsubscribe` / `thread/loaded/list` | `{threadId}` / `{}` | common.rs:624, 926 |
| **`turn/start`** | `threadId`, `input:[UserInput]`, `cwd?`, `approvalPolicy?`, `approvalsReviewer?`, `sandboxPolicy?`, `model?`, `effort?`, `summary?`, `serviceTier?`, `outputSchema?`, `clientUserMessageId?`, `additionalContext?` | `v2/turn.rs:190-330`; common.rs:1148 |
| `turn/steer` | `{threadId, input:[UserInput], clientUserMessageId?}` (往运行中的轮次插话) | `v2/turn.rs:331-345` |
| `turn/interrupt` | `{threadId, turnId}` | `v2/turn.rs:374-382` |
| `turn/settings/update` | `{threadId,turnId,model?,effort?,summary?,approvalsReviewer?}` | `v2/turn.rs:53-96` |
| `review/start` | `{threadId, ...}` | common.rs:1258 |
| `model/list` | `{modelProvider?,cursor?,limit?,includeHidden?}` → `{data:[Model],nextCursor}` | `v2/model.rs:55-68, 141-205` |
| `modelProvider/list` / `modelProvider/config/write` | 配置读写 | common.rs:1280+ |
| `config/read` / `config/value/write` / `config/batchWrite` | 读写 config.toml | common.rs |
| `fs/readFile` `fs/writeFile` `fs/createDirectory` `fs/getMetadata` `fs/readDirectory` `fs/remove` `fs/copy` `fs/watch` `fs/unwatch` | 文件系统（并发） | common.rs:1090-1130 |
| `command/exec` (+`/outputDelta`,`/write`,`/resize`,`/terminate`) | 客户端侧直接跑命令、流式 stdout/stderr | common.rs |
| `process/spawn` `/writeStdin` `/kill` `/resizePty` | PTY 会话 | common.rs |
| `skills/list` `skills/config/write` `hooks/list` `plugin/*` `app/list` `app/read` | 扩展能力 | common.rs:980-1140 |
| `fuzzyFileSearch` | 文件模糊搜索 | common.rs |
| `getAuthStatus` `getConversationSummary` `gitDiffToRemote` | 旧版 v1 兼容方法 | `protocol/v1.rs` |

> 客户端 → 服务端的通知只有一个：`initialized`（无 params），紧跟 `initialize` 之后发送。
> 来源 `protocol/common.rs:2251-2253`（`client_notification_definitions! { Initialized }`）

### A2. 服务端 → 客户端 通知（`server_notification_definitions!`，`protocol/common.rs:2099-2240`）

会话/轮次主链路（复刻必做）：

| method | payload 关键字段 | 来源 |
|---|---|---|
| `thread/started` | `{thread}` | thread.rs:2305 |
| `thread/status/changed` | `{threadId, status: notLoaded/idle/systemError/active{activeFlags:[waitingOnApproval,waitingOnUserInput]}}` | thread.rs:1810-1815, 2312 |
| `thread/name/updated` | `{threadId,name}` | common.rs:2112 |
| `turn/started` | `{threadId, turn}` | turn.rs |
| `turn/completed` | `{threadId, turn:{id,items,status:completed/interrupted/failed/inProgress,error?,startedAt,completedAt,durationMs}}` | `v2/turn.rs:624-627`, `v2/thread_data.rs:401-425` |
| `turn/diff/updated` | `{threadId,turnId,diff}` (整轮聚合 unified diff) | turn.rs:634 |
| `turn/plan/updated` | `{threadId,turnId,plan}` | common.rs:2137 |
| `item/started` | `{threadId,turnId,item,startedAtMs}` | item.rs:1434 |
| `item/completed` | `{threadId,turnId,item,contentTokenCount?,completedAtMs}` | item.rs:1531 |
| `item/agentMessage/delta` | `{threadId,turnId,itemId,delta}` ← 正文流 | item.rs:1576 |
| `item/reasoning/summaryTextDelta` | `{threadId,turnId,itemId,delta,summaryIndex}` ← 推理摘要流 | item.rs:1598 |
| `item/reasoning/summaryPartAdded` | `{threadId,turnId,itemId,summaryIndex}` | item.rs:1610 |
| `item/reasoning/textDelta` | `{threadId,turnId,itemId,delta,contentIndex}` ← 原始 CoT(若开) | item.rs:1621 |
| `item/plan/delta` (exp) | `{threadId,turnId,itemId,delta}` | item.rs:1588 |
| `item/commandExecution/outputDelta` | `{...,delta}` 命令 stdout/stderr | common.rs:2161 |
| `item/fileChange/patchUpdated` | apply_patch 进度 | common.rs:2165 |
| `thread/tokenUsage/updated` | `{threadId,turnId,tokenUsage:{total:{...},last:{...},modelContextWindow}}` | `thread.rs:2211-2298` |
| `account/updated` | `{authMode?, planType?}` | account.rs:655 |
| `account/login/completed` | `{loginId, success, error?}` | common.rs:2224 |
| `account/rateLimits/updated` | 速率窗口 | common.rs:2180 |
| `error` | `{message, ...}` | common.rs:2101 |
| `warning` / `configWarning` / `deprecationNotice` | 提示 | common.rs:2200+ |
| `serverRequest/resolved` | `{requestId}` 审批已被别处解决 | common.rs:2166 |
| `model/rerouted` | `{fromModel,toModel,reason}` | model.rs:210 |
| `thread/compacted` | 压缩完成（deprecated → 用 ContextCompaction item） | common.rs:2185 |

### A3. 服务端 → 客户端 请求（`server_request_definitions!`，`protocol/common.rs:1951-1995`）

客户端必须回带同 `id` 的 `result`，否则 agent 会卡住：

| method | params | 期望 result | 来源 |
|---|---|---|---|
| `item/commandExecution/requestApproval` | `{kind,threadId,turnId,itemId,approvalId?,startedAtMs,command?,cwd?,reason?,proposedExecpolicyAmendment?}` | `{"decision":"accept"\|"acceptForSession"\|"decline"\|"cancel"\|"acceptWithExecpolicyAmendment"{execpolicyAmendment}\|"applyNetworkPolicyAmendment"{networkPolicyAmendment}}` | item.rs:1692-1770 |
| `item/fileChange/requestApproval` | `{threadId,turnId,itemId,startedAtMs,reason?,grantRoot?}` | `{"decision":"accept"\|"acceptForSession"\|"decline"\|"cancel"}` | item.rs:1775-1795 |
| `item/permissions/requestApproval` | `{threadId,turnId,itemId,cwd,reason?,permissions{...},startedAtMs}` | 权限授予（turn/session 作用域） | permissions.rs:846-866 |
| `item/tool/requestUserInput` (exp) | `{threadId,turnId,itemId,questions:[...],isBlocking}` | 用户回答 | item.rs:2001-2010 |
| `item/tool/call` | 动态工具调用（客户端实现工具） | `DynamicToolCallResult` | common.rs:1986 |
| `mcpServer/elicitation/request` | MCP 询问 |  | common.rs:1974 |
| `account/chatgptAuthTokens/refresh` | `{reason:"unauthorized", previousAccountId?}` | `{accessToken, chatgptAccountId, chatgptPlanType?}` | account.rs:311-340 |

### A4. 关键 payload 结构

`ThreadItem`（`v2/item.rs:322-`，tag = `type`）：
`userMessage{id,clientId?,content:[UserInput]}`、`agentMessage{id,text,phase?}`、
`reasoning{id,summary:[string],content:[string]}`、`plan{id,text}`、
`commandExecution{...}`、`fileChange{...}`、`mcpToolCall{...}`、`functionCallOutput{id,name,namespace?,output}`、
`contextCompaction`、`subAgentActivity{...}`。

`UserInput`（`codex-rs/protocol/src/user_input.rs:17-56`，tag = `type`）：
```json
{"type":"text","text":"...","textElements":[]}
{"type":"image","imageUrl":"..."} | {"type":"localImage","path":"/abs.png","detail?":"high"}
{"type":"audio","...":"..."} | {"type":"localAudio","path":"..."}
{"type":"skill","name":"...","path":"..."}  | {"type":"mention","..."}
```
注意 `text` 的 `textElements` 用 **byte range**（UTF-8 字节偏移），`{byteRange:{start,end},placeholder}`。

`Thread`（`v2/thread_data.rs:205-230`）：`{id, sessionId, forkedFromId, parentThreadId, preview, modelProvider, createdAt, updatedAt, status, cwd, ...}`。

`ReasoningEffort`（`codex-rs/protocol/src/openai_models.rs:76-106`）线上值：
`none | minimal | low | medium | high | xhigh | max | ultra | persistent`（默认 `medium`；另有 `Custom(String)` 透传）。
`ReasoningSummary`（`config_types.rs:65-72`）：`auto | concise | detailed | none`（默认 `auto`）。
`AskForApproval`（`protocol.rs:1171-1194`）：`untrusted | on-request | on-failure(alias) | never | granular{...}`。
`SandboxMode`（`config_types.rs:104-114`）：`read-only | workspace-write | danger-full-access`。
`SandboxPolicy`（`protocol.rs:1258-1300`，tag=`type`）：`danger-full-access` /
`read-only{networkAccess?}` / `workspace-write{writableRoots?,networkAccess?,...}` / `external-sandbox{networkAccess}`。

`Model`（`v2/model.rs:141-180`）：`{id, model, upgrade, upgradeInfo, displayName, description, hidden,
supportedReasoningEfforts:[{effort,description}], defaultReasoningEffort, inputModalities, serviceTiers, ...}`。

## B) 一次完整会话的时序（伪 JSON，一行一条）

```jsonl
→ {"id":1,"method":"initialize","params":{"clientInfo":{"name":"gm_agent","title":"GM Agent","version":"0.1.0"},"capabilities":{"experimentalApi":false}}}
← {"id":1,"result":{"userAgent":"codex_cli_rs/0.x ...","codexHome":"/root/.codex","platformFamily":"unix","platformOs":"linux"}}
→ {"method":"initialized"}
→ {"id":2,"method":"account/read","params":{"refreshToken":false}}
← {"id":2,"result":{"account":{"type":"chatgpt","email":"a@b.c","planType":"plus"},"requiresOpenaiAuth":true}}
→ {"id":3,"method":"model/list","params":{"limit":50}}
← {"id":3,"result":{"data":[{"id":"gpt-5.4","model":"gpt-5.4","displayName":"GPT-5.4","supportedReasoningEfforts":[{"effort":"low"},{"effort":"medium"},{"effort":"high"},{"effort":"xhigh"}],"defaultReasoningEffort":"medium"}],"nextCursor":null}}
→ {"id":4,"method":"thread/start","params":{"model":"gpt-5.4","cwd":"/work","approvalPolicy":"on-request","sandbox":"workspace-write"}}
← {"id":4,"result":{"thread":{"id":"0192f...-uuid7","sessionId":"...","status":{"type":"idle"},"preview":""},"model":"gpt-5.4","modelProvider":"openai","cwd":"/work","approvalPolicy":"on-request","sandbox":{...}}}
← {"method":"thread/started","params":{"thread":{"id":"0192f...","status":{"type":"idle"}},"emittedAtMs":1764...}}
→ {"id":5,"method":"turn/start","params":{"threadId":"0192f...","input":[{"type":"text","text":"列出 /work"}],"effort":"medium","summary":"auto"}}
← {"id":5,"result":{"turn":{"id":"0192f...-turn","status":"inProgress","items":[]}}}
← {"method":"turn/started","params":{"threadId":"0192f...","turn":{"id":"...turn","status":"inProgress","items":[]}}}
← {"method":"item/started","params":{"threadId":"...","turnId":"...turn","item":{"type":"reasoning","id":"it_1","summary":[],"content":[]},"startedAtMs":...}}
← {"method":"item/reasoning/summaryTextDelta","params":{"threadId":"...","turnId":"...","itemId":"it_1","delta":"用户想要","summaryIndex":0}}
← {"method":"item/completed","params":{"threadId":"...","turnId":"...","item":{"type":"reasoning","id":"it_1","summary":["..."]},"completedAtMs":...}}
← {"method":"item/started","params":{...,"item":{"type":"agentMessage","id":"it_2","text":""}}}
← {"method":"item/agentMessage/delta","params":{"threadId":"...","turnId":"...","itemId":"it_2","delta":"我会先"}}
← {"method":"item/started","params":{...,"item":{"type":"commandExecution","id":"it_3","command":"ls -la","status":"running"}}}
← {"method":"item/commandExecution/outputDelta","params":{...,"itemId":"it_3","delta":"total 0\n"}}
S→C {"id":900,"method":"item/commandExecution/requestApproval","params":{"kind":"command","threadId":"...","turnId":"...","itemId":"it_3","startedAtMs":...,"command":"rm -rf /tmp/x","cwd":"/work","reason":"needs write"}}
C→S {"id":900,"result":{"decision":"acceptForSession"}}
← {"method":"item/completed","params":{...,"item":{"type":"agentMessage","id":"it_2","text":"...完整文本..."}}}
← {"method":"thread/tokenUsage/updated","params":{"threadId":"...","turnId":"...","tokenUsage":{"total":{"totalTokens":1234,"inputTokens":1000,"cachedInputTokens":800,"cacheWriteInputTokens":0,"outputTokens":234,"reasoningOutputTokens":80},"last":{...},"modelContextWindow":1050000}}}
← {"method":"turn/completed","params":{"threadId":"...","turn":{"id":"...turn","status":"completed","items":[...],"error":null,"startedAt":...,"completedAt":...}}}
```

中止：`→ {"id":6,"method":"turn/interrupt","params":{"threadId":"...","turnId":"...turn"}}` → `turn/completed` 的 `turn.status = "interrupted"`。

## C) 认证与配置要点

### C1. 两种 ChatGPT OAuth 流程（都在 app-server 内部完成，客户端只当 UI）

**通用端点**：issuer 默认 `https://auth.openai.com`（`login/src/server.rs:78` `DEFAULT_ISSUER`）
client_id = **`app_EMoamEEZ73f0CkXaXp7hrann`**（`login/src/auth/manager.rs:1897` `pub const CLIENT_ID`；
可被环境变量 `CODEX_APP_SERVER_LOGIN_CLIENT_ID` 覆盖，`manager.rs:245`）
scope = `openid profile email offline_access api.connectors.read api.connectors.invoke`
（`server.rs:610-614`）
授权端点 `POST/GET {issuer}/oauth/authorize`，换取 `POST {issuer}/oauth/token`（form-encoded，
`grant_type=authorization_code`，RFC 7636 PKCE S256）（`server.rs:615, 719, 826`）

**1) 浏览器 PKCE（`account/login/start` type=`chatgpt`）**
- 客户端起本地 HTTP 监听 `http://127.0.0.1:{port}/auth/callback`（首选端口，失败回退；`server.rs:197, 670-700`）
- 附加参数：`id_token_add_organizations=true`、`codex_cli_simplified_flow=true`、`originator=<originator>`
  （如 `codex_cli_rs`），可选 `allowed_workspace_id` / `current_workspace_id` / `login_hint`（`server.rs:585-618`）
- 返回 `{"type":"chatgpt","loginId":"<uuid>","authUrl":"https://auth.openai.com/oauth/authorize?..."}`
- 完成后推送通知 `account/login/completed {loginId,success,error?}`

**2) Device Code（`account/login/start` type=`chatgptDeviceCode`）— iOS 首选**
（`login/src/device_code_auth.rs:1-240`）
```
POST {issuer}/api/accounts/deviceauth/usercode   body {"client_id":"app_EMoamEEZ73f0CkXaXp7hrann"}
  → {"device_auth_id":"...","user_code":"ABCD-1234","interval":"5"}        // interval 是字符串
用户打开 {issuer}/codex/device 输入 user_code
POST {issuer}/api/accounts/deviceauth/token       body {"device_auth_id":"...","user_code":"..."}
  轮询 ≤15 分钟，间隔 interval 秒 → {"authorization_code":"...","code_challenge":"...","code_verifier":"..."}
POST {issuer}/oauth/token  grant_type=authorization_code&code=<authorization_code>
     &redirect_uri={issuer}/deviceauth/callback&code_verifier=<verifier>&client_id=<CLIENT_ID>
  → {id_token, access_token, refresh_token}
```
app-server 返回给 UI：`{"type":"chatgptDeviceCode","loginId":"...","verificationUrl":"https://auth.openai.com/codex/device","userCode":"ABCD-1234"}`

**3) 客户端自管 token（自研客户端推荐，跳过内置 OAuth）**
`account/login/start` + `{"type":"chatgptAuthTokens","accessToken":"<JWT>","chatgptAccountId":"<acc>","chatgptPlanType":"plus"}`
（`v2/account.rs:101-116`，标注 UNSTABLE/内部用）。之后遇 401，服务端反向请求
`account/chatgptAuthTokens/refresh`，客户端回 `{accessToken, chatgptAccountId, chatgptPlanType?}`。

### C2. 本地 token 存储

- 路径：`$CODEX_HOME/auth.json`，`CODEX_HOME` 默认 `~/.codex`（`login/src/auth/storage.rs:167-169`）
- schema（`storage.rs:53-77`）：camelCase 不适用，字段原名如下
  ```json
  {
    "auth_mode": "chatgpt",                  // 或 apikey / chatgptAuthTokens / personalAccessToken
    "OPENAI_API_KEY": null,
    "tokens": {
      "id_token": "<raw jwt string>",
      "access_token": "<jwt>",
      "refresh_token": "<opaque>",
      "account_id": "<chatgpt account id>",
      "oauth_provenance": {"issuer":"https://auth.openai.com","client_id":"app_EMoamEEZ73f0CkXaXp7hrann"},
      "login_owner_id": "<uuid>"
    },
    "last_refresh": "2026-06-01T12:00:00Z",
    "personal_access_token": null,
    "agent_identity": null
  }
  ```
  注意：`tokens.id_token` 在文件中是**字符串**，反序列化时由 `deserialize_id_token` 展开成扁平字段
  （`token_data.rs:11-40`）。
- JWT claims（`token_data.rs:60-100`）：
  `https://api.openai.com/auth` → `chatgpt_plan_type`(free/plus/pro/business/enterprise/edu),
  `chatgpt_user_id`, `chatgpt_account_id`, `chatgpt_account_is_fedramp`；
  `https://api.openai.com/profile` → `email`；标准 `exp`。
- 也支持 keyring / secrets 后端，由 `cli_auth_credentials_store` 选择（`core/src/config/auth_keyring.rs`）。
- 后端推理 base URL（`model-provider-info/src/lib.rs:88`）：
  `CHATGPT_CODEX_BASE_URL = "https://chatgpt.com/backend-api/codex"`（ChatGPT 登录态）
  vs `https://api.openai.com/v1`（API key 态）；`wire_api = "responses"`（`chat` 已移除，`lib.rs:113`）。

### C3. `~/.codex/config.toml` 关键键（`config/src/config_toml.rs:177-420`）

| 键 | 取值/说明 |
|---|---|
| `model` | slug，如 `"gpt-5.4"` |
| `model_provider` | provider id，内置 `"openai"` |
| `model_context_window` / `model_auto_compact_token_limit` | int |
| `approval_policy` | `untrusted`/`on-request`/`never`/`granular{...}` |
| `approvals_reviewer` | 审批路由（如自动复核） |
| `sandbox_mode` | `read-only`/`workspace-write`/`danger-full-access` |
| `sandbox_workspace_write` | `{writable_roots=[...], network_access=bool, ...}` |
| `model_reasoning_effort` | `minimal`…`xhigh`/`ultra` 等 |
| `model_reasoning_summary` | `auto`/`concise`/`detailed`/`none` |
| `developer_instructions` / `instructions` | 系统提示覆盖 |
| `forced_login_method` / `forced_chatgpt_workspace_id` | 锁定登录方式/工作区 |
| `cli_auth_credentials_store` | `file`/`keyring`/`auto` |
| `chatgpt_base_url` | 覆盖 ChatGPT 后端（镜像/网关） |
| `[model_providers.<id>]` | `name`,`base_url`,`wire_api="responses"`,`env_key`,`http_headers`,`requires_openai_auth`,`supports_websockets`,`query_params`,`request_max_retries`,`stream_idle_timeout_ms` |
| `[mcp_servers.<id>]` | MCP 服务器 |
| `profile` / `[profiles.<name>]` | 配置档案 |
| `[analytics] enabled` | app-server 默认关闭 |

### C4. 模型标识与 reasoning effort

- Codex 用**纯 slug 字符串**引用模型：`gpt-5`、`gpt-5.4`、`gpt-5.4-mini`、`gpt-5.3-codex` 等，
  见源码测试/示例 `gpt-5`(`protocol/common.rs:3415`)、`gpt-5.4`(`common.rs:4666`)、`gpt-5.4-mini`(`protocol/thread_history.rs:5207`)。
  Codex 不硬编码清单，实际列表来自 `model/list`（服务端模型目录）。
- models.dev (`https://models.dev/api.json`, 抓取当次) openai 域可见 gpt-5 系列 slug 与 effort 集合：
  `gpt-5`, `gpt-5-mini`, `gpt-5-nano`, `gpt-5.1`, `gpt-5.2`, `gpt-5.2-pro`, `gpt-5.3-codex`, `gpt-5.4`,
  `gpt-5.4-mini`, `gpt-5.4-nano`, `gpt-5.4-pro`, `gpt-5.5`, `gpt-5.5-pro`, `gpt-5.6`(+`-terra`/`-luna`/`-sol`), `gpt-5-pro`；
  `reasoning_options = [{type:"effort", values:["none","low","medium","high","xhigh"]}]`（gpt-5.4 / gpt-5.4-mini / gpt-5.3-codex 一致）。
- Codex 端 wire 值更宽：`none|minimal|low|medium|high|xhigh|max|ultra|persistent` + 任意自定义串透传
  （`openai_models.rs:76-106`）。**以 `model/list` 返回的 `supportedReasoningEfforts` 为准**，不要硬编码。

### C5. 可参考的既有实现
- 官方/一等公民客户端：VS Code 扩展、Codex TUI、Codex App(macOS)，都走同一 app-server 协议。
- `codex-rs/app-server-client` crate 是官方 Rust 客户端参考实现（`src/lib.rs`, `src/server_request.rs`, `src/tests/reply_tests.rs`）。
- **第三方 iOS/macOS 轻量复刻：未核实**（本次未在 GitHub 检索到可确认的公开项目）。

## D) 可直接落地的 10 条结论

1. **传输就是 NDJSON over stdio**：`codex app-server --listen stdio://`，一行一条 JSON，**没有** `jsonrpc` 字段；
   用 `NSTask`(iOS 上不可用) → 你内置的 arm64 二进制用 `popen`/`posix_spawn` + 两条 pipe，ObjC 侧按 `\n` 切帧即可。
2. **三报文判定极简**：有 `id`+`result`/`error` = 响应；有 `id`+`method` = 服务端请求（必须回 `{"id":same,...}`）；
   只有 `method` = 通知。忽略未知 `method` 是安全的（向前兼容）。
3. **握手顺序固定**：`initialize`（带 `clientInfo{name,title,version}`）→ 收 `{userAgent,codexHome,platformFamily,platformOs}`
   → 发 `initialized` 通知。不做这步后续全部失败。
4. **会话最小闭环只需 4 个方法**：`thread/start` → `turn/start` → 消费 `item/agentMessage/delta` +
   `item/reasoning/summaryTextDelta` → 以 `turn/completed` 收尾；中断用 `turn/interrupt`。
5. **UI 增量渲染三件套**：`item/started` 建行 → `*/delta`（`agentMessage` / `reasoning.summaryTextDelta` /
   `commandExecution.outputDelta`）追加文本 → `item/completed` 用最终 `item.text` **整体替换**（delta 不保证等于全文）。
6. **必须实现审批回环**，否则 agent 卡死：处理 `item/commandExecution/requestApproval`（回
   `accept/acceptForSession/decline/cancel`）与 `item/fileChange/requestApproval`；`turn/completed.status`
   出现 `interrupted/failed` 时读 `turn.error`。
7. **token 用量**取 `thread/tokenUsage/updated` 的 `tokenUsage.{total,last}.{totalTokens,inputTokens,
   cachedInputTokens,cacheWriteInputTokens,outputTokens,reasoningOutputTokens}` + `modelContextWindow`（画上下文进度条）。
8. **认证走 device code 最省事**：`account/login/start` + `{"type":"chatgptDeviceCode"}` 拿
   `verificationUrl`+`userCode`，用 ASWebAuthenticationSession 打开 `https://auth.openai.com/codex/device`；
   或自己实现 `POST /api/accounts/deviceauth/usercode` → 轮询 `/deviceauth/token` → `/oauth/token`，
   client_id `app_EMoamEEZ73f0CkXaXp7hrann`，scope 含 `openid profile email offline_access api.connectors.read api.connectors.invoke`。
9. **token 持久化对齐 `$CODEX_HOME/auth.json`**（`tokens.{id_token,access_token,refresh_token,account_id}` +
   `last_refresh`），把 iOS 侧拿到的 token 写进去即可让内置二进制「已登录」；或直接走
   `account/login/start` 的 `chatgptAuthTokens` 注入 access token + `chatgptAccountId`。
10. **模型与 effort 不要硬编码**：启动后调 `model/list`，用 `id`/`model` slug、`displayName`、
    `supportedReasoningEfforts[]`、`defaultReasoningEffort` 生成选择器；`turn/start` 传 `model` + `effort`
    （wire 值 `low|xhigh|...`）。沙箱/审批同理留给 `thread/start` 的 `sandbox`/`approvalPolicy` 或 `config.toml`。
