import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

SERVICE_NAME = os.environ.get("SERVICE_NAME", "unknown")
PORT = int(os.environ.get("PORT", "8080"))


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps({"service": SERVICE_NAME, "status": "mock", "path": self.path}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
