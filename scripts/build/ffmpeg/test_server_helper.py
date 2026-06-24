#!/usr/bin/env python3
"""Minimal HTTP/HTTPS file server for ffmpeg fixture tests.

Binds to 127.0.0.1:0 (OS-assigned port), writes the port number
atomically to --port-file, then serves files from --directory.

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

    handler = lambda *a, **kw: http.server.SimpleHTTPRequestHandler(
        *a, directory=args.directory, **kw
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
