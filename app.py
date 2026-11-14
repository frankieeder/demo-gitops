# The whole app: a web page that says which environment and commit it's running.
# Change MESSAGE, push, and watch it flow through to the cluster.
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

MESSAGE = "Hello from GitOps"
ENV = os.getenv("APP_ENV", "unknown")
COMMIT = os.getenv("COMMIT", "local")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = f"<h1>{MESSAGE}</h1><p>environment: <b>{ENV}</b></p><p>commit: {COMMIT[:7]}</p>"
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        self.wfile.write(body.encode())


HTTPServer(("", 8000), Handler).serve_forever()
