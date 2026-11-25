import http.server, json, time, os, sys

class H(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0))
        body = json.loads(self.rfile.read(n))
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Transfer-Encoding', 'chunked')
        self.end_headers()

        def chunk(s):
            b = s.encode()
            self.wfile.write(("%X\r\n" % len(b)).encode() + b + b"\r\n")
            self.wfile.flush()

        msgs = body.get('messages', [])
        has_tool = any(m.get('role') == 'tool' for m in msgs)

        def ev(obj):
            chunk("data: " + json.dumps(obj, ensure_ascii=False) + "\n\n")

        if not has_tool:
            for t in ["我先", "跑一下", "命令"]:
                ev({"choices": [{"delta": {"content": t}}]})
                time.sleep(0.05)
            ev({"choices": [{"delta": {"tool_calls": [{
                "index": 0, "id": "call_1",
                "function": {"name": "shell",
                             "arguments": json.dumps({"command": "echo gm-alive"})}}]},
                "finish_reason": "tool_calls"}]})
        else:
            out = [m for m in msgs if m.get('role') == 'tool'][-1]['content'].strip()
            ev({"choices": [{"delta": {"content": "命令输出是: " + out}, "finish_reason": "stop"}]})
            ev({"usage": {"prompt_tokens": 12, "completion_tokens": 7}})

        chunk("data: [DONE]\n\n")
        self.wfile.write(b"0\r\n\r\n")
        self.wfile.flush()

    def log_message(self, *a):
        pass

port = int(os.environ.get('GM_MOCK_PORT', '8771'))
srv = http.server.ThreadingHTTPServer(('127.0.0.1', port), H)
sys.stderr.write('mock listening on %d\n' % port)
srv.serve_forever()
