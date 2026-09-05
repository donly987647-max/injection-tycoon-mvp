#!/usr/bin/env python3
"""Serve Godot Web export (non-threaded; GitHub Pages compatible)."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import os
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "build", "web")
HOST = "0.0.0.0"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765


class Handler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "application/javascript",
    }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=os.path.abspath(ROOT), **kwargs)

    def end_headers(self):
        # No COOP/COEP: export uses variant/thread_support=false for Pages.
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


def main() -> None:
    root = os.path.abspath(ROOT)
    if not os.path.isdir(root):
        print("Missing web build at", root, file=sys.stderr)
        sys.exit(1)
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Serving {root} at http://{HOST}:{PORT}/ (thread_support=false)")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
