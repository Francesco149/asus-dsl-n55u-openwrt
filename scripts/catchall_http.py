#!/usr/bin/env python3
"""Log every HTTP request the router makes while it believes we are the internet.

Usage: catchall_http.py <logfile> [port]
Every DNS name resolves to us (dnsmasq --address=/#/...), so firmware-update
checks, NTP-over-HTTP fallbacks, DDNS, etc. all land here.
"""
import http.server
import json
import sys
import time

LOG = sys.argv[1]
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 80


class H(http.server.BaseHTTPRequestHandler):
    def _handle(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n) if n else b""
        rec = {
            "t": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "src": self.client_address[0],
            "method": self.command,
            "path": self.path,
            "headers": dict(self.headers),
            "body": body.decode("latin-1"),
        }
        with open(LOG, "a") as f:
            f.write(json.dumps(rec) + "\n")
        self.send_response(404)
        self.send_header("Content-Length", "0")
        self.end_headers()

    do_GET = do_POST = do_HEAD = do_PUT = _handle

    def log_message(self, *a):
        pass


http.server.ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
