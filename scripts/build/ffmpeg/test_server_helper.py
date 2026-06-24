#!/usr/bin/env python3
"""Minimal HTTP/HTTPS file server for ffmpeg fixture tests.

Binds to 127.0.0.1:0 (OS-assigned port), writes the port number
atomically to --port-file, then serves files from --directory.

Supports HTTP Range requests (required for ffmpeg MP4 demuxing over HTTP).

HTTPS mode: pass --https --cert CERT --key KEY.
Shutdown: SIGTERM closes the listening socket and exits.
"""
import argparse
import http.server
import os
import signal
import ssl
import sys
import tempfile
import threading


class RangeHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    """SimpleHTTPRequestHandler with HTTP Range request support."""

    def do_GET(self):
        if "Range" not in self.headers:
            return super().do_GET()

        path = self.translate_path(self.path)
        if os.path.isdir(path):
            return super().do_GET()

        range_header = self.headers["Range"]
        if not range_header.startswith("bytes="):
            return super().do_GET()

        try:
            f = open(path, "rb")
        except OSError:
            self.send_error(404, "File not found")
            return

        file_size = os.fstat(f.fileno()).st_size
        range_spec = range_header[6:]
        start_str, end_str = range_spec.split("-", 1)
        start = int(start_str) if start_str else 0
        end = int(end_str) if end_str else file_size - 1
        end = min(end, file_size - 1)

        if start >= file_size:
            f.close()
            self.send_error(416, "Range Not Satisfiable")
            return

        content_length = end - start + 1
        ctype = self.guess_type(path)

        self.send_response(206)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(content_length))
        self.send_header("Content-Range", f"bytes {start}-{end}/{file_size}")
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()

        f.seek(start)
        remaining = content_length
        while remaining > 0:
            chunk = f.read(min(65536, remaining))
            if not chunk:
                break
            self.wfile.write(chunk)
            remaining -= len(chunk)
        f.close()

    def end_headers(self):
        self.send_header("Accept-Ranges", "bytes")
        super().end_headers()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port-file", required=True)
    parser.add_argument("--directory", required=True)
    parser.add_argument("--https", action="store_true")
    parser.add_argument("--cert")
    parser.add_argument("--key")
    args = parser.parse_args()

    if args.https and (not args.cert or not args.key):
        print("FATAL: --https requires --cert and --key", file=sys.stderr)
        sys.exit(1)

    directory = args.directory

    handler = lambda *a, **kw: RangeHTTPRequestHandler(
        *a, directory=directory, **kw
    )

    server = http.server.HTTPServer(("127.0.0.1", 0), handler)

    if args.https:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(args.cert, args.key)
        server.socket = ctx.wrap_socket(server.socket, server_side=True)

    port = server.server_address[1]

    # Atomic write: tmpfile + rename
    port_dir = os.path.dirname(os.path.abspath(args.port_file))
    fd, tmp = tempfile.mkstemp(dir=port_dir)
    with os.fdopen(fd, "w") as f:
        f.write(str(port))
    os.rename(tmp, args.port_file)

    def shutdown(signum, frame):
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, shutdown)

    print(f"Serving on 127.0.0.1:{port} (HTTPS={args.https})", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
