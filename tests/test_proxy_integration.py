"""Run the real NPM role against an in-process fake API, never the VPS."""
import copy
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import threading

ROOT = Path(__file__).resolve().parents[1]


def test_proxy_reconciliation_create_idempotence_and_updates():
    state = {"hosts": [], "certificates": [], "writes": 0}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def respond(self, value, status=200):
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(value).encode())

        def do_GET(self):
            key = "certificates" if self.path.endswith("certificates") else "hosts"
            self.respond(state[key])

        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            if self.path == "/api/tokens":
                self.respond({"token": "synthetic-token"})
                return
            key = "certificates" if self.path.endswith("certificates") else "hosts"
            body["id"] = len(state[key]) + 1
            state[key].append(body)
            state["writes"] += 1
            self.respond(body, 201)

        def do_PUT(self):
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            number = int(self.path.rsplit("/", 1)[1])
            body["id"] = number
            state["hosts"][number - 1] = body
            state["writes"] += 1
            self.respond(body)

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    def reconcile(check=False):
        args = ["ansible-playbook", "-i", "tests/inventory/hosts.yml", "tests/proxy-check.yml", "-e", json.dumps({"npm_base_url": "http://127.0.0.1", "npm_admin_port": server.server_port})]
        if check:
            args.append("--check")
        result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True, timeout=90)
        assert result.returncode == 0, result.stdout + result.stderr

    try:
        reconcile(check=True)
        assert state["writes"] == 0
        reconcile()
        assert len(state["hosts"]) == len(state["certificates"]) == 5
        assert all(host["certificate_id"] > 0 for host in state["hosts"])
        baseline = copy.deepcopy(state)
        reconcile()
        assert state == baseline
        state["hosts"][0]["locations"] = [{"path": "/outdated"}]
        state["hosts"][0]["hsts_subdomains"] = True
        reconcile()
        assert state["hosts"][0]["locations"] == []
        assert state["hosts"][0]["hsts_subdomains"] is False
        assert state["writes"] == baseline["writes"] + 1
        state["hosts"][0]["hsts_subdomains"] = True
        reconcile()
        assert state["hosts"][0]["hsts_subdomains"] is False
        assert state["writes"] == baseline["writes"] + 2
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
