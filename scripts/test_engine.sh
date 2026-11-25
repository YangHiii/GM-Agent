#!/bin/sh
# GM Agent · 引擎回归（离线，含 mock 提供方端到端）
set -e
cd "$(dirname "$0")/.."
CC=${CC:-cc}
BIN=${TMPDIR:-/tmp}/gm-engine-test
echo "== 编译"
$CC -std=gnu99 -O2 -Wall -Iengine -o "$BIN" engine/*.c -lssl -lcrypto -lz

echo "== 协议往返"
REQ='{"jsonrpc":"2.0","id":1,"method":"gm/initialize","params":{}}
{"jsonrpc":"2.0","id":"b","method":"gm/thread/start"}
{"jsonrpc":"2.0","id":3,"method":"gm/ping"}
{"jsonrpc":"2.0","id":4,"method":"gm/unknown"}'
OUT=$(printf '%s\n' "$REQ" | "$BIN" --mode app-server 2>/dev/null)
echo "$OUT"
echo "$OUT" | grep -q '"protocol":"gm-1"'  || { echo FAIL init; exit 1; }
echo "$OUT" | grep -q '"thread"'          || { echo FAIL thread; exit 1; }
echo "$OUT" | grep -q 'pong'              || { echo FAIL ping; exit 1; }
echo "$OUT" | grep -q 'method not found'  || { echo FAIL unknown; exit 1; }

echo "== 工具执行"
printf '{"id":1,"method":"gm/tool/shell","params":{"command":"echo gm-ok; exit 3"}}\n' \
  | "$BIN" --mode app-server 2>/dev/null | grep -q '"code":3' || { echo FAIL shell; exit 1; }

echo "== 端到端（mock 提供方 → 工具调用 → 回填）"
PORT=$((18000 + $$ % 1000))
GM_MOCK_PORT=$PORT python3 scripts/mock_provider.py 2>/dev/null & MOCK=$!
sleep 1.5
E2E=$(printf '{"id":1,"method":"gm/thread/start"}\n{"id":2,"method":"gm/turn/start","params":{"text":"run echo"}}\n' \
  | GM_BASE_URL="http://127.0.0.1:$PORT/v1/chat/completions" "$BIN" --mode app-server 2>/dev/null)
kill $MOCK 2>/dev/null || true
echo "$E2E" | tail -6
echo "$E2E" | grep -q 'gm/event/toolCall'   || { echo FAIL toolCall; exit 1; }
echo "$E2E" | grep -q 'gm/event/toolResult' || { echo FAIL toolResult; exit 1; }
echo "$E2E" | grep -q 'gm-alive'            || { echo FAIL tool output; exit 1; }
echo "$E2E" | grep -q '"finish":"stop"'     || { echo FAIL turnEnd; exit 1; }
echo "全部通过"
