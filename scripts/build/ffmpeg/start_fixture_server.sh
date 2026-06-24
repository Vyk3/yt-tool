#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Usage: start_fixture_server.sh [--https --cert CERT --key KEY] --port-file FILE --directory DIR
# Output: PORT_FILE contains the port number, PORT_FILE.pid contains the server PID,
#         PORT_FILE.log contains server logs.
# Caller reads PID via: cat "${PORT_FILE}.pid"

PORT_FILE=""
DIRECTORY=""
HTTPS_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port-file) PORT_FILE="$2"; shift 2 ;;
    --directory) DIRECTORY="$2"; shift 2 ;;
    --https)     HTTPS_ARGS+=(--https); shift ;;
    --cert)      HTTPS_ARGS+=(--cert "$2"); shift 2 ;;
    --key)       HTTPS_ARGS+=(--key "$2"); shift 2 ;;
    *) echo "FATAL: unknown arg $1" >&2; exit 1 ;;
  esac
done

[[ -n "$PORT_FILE" ]] || { echo "FATAL: --port-file required" >&2; exit 1; }
[[ -n "$DIRECTORY" ]] || { echo "FATAL: --directory required" >&2; exit 1; }

TIMEOUT=10
LOG_FILE="${PORT_FILE}.log"

python3 "$SCRIPT_DIR/test_server_helper.py" \
  "${HTTPS_ARGS[@]+"${HTTPS_ARGS[@]}"}" \
  --port-file "$PORT_FILE" \
  --directory "$DIRECTORY" \
  > "$LOG_FILE" 2>&1 &
SERVER_PID=$!

echo "$SERVER_PID" > "${PORT_FILE}.pid"

ELAPSED=0
while [[ ! -s "$PORT_FILE" ]]; do
  sleep 0.2; ELAPSED=$((ELAPSED + 1))
  if (( ELAPSED > TIMEOUT * 5 )); then
    kill "$SERVER_PID" 2>/dev/null || true
    echo "FATAL: server failed to start within ${TIMEOUT}s" >&2
    cat "$LOG_FILE" >&2 2>/dev/null || true
    exit 1
  fi
  kill -0 "$SERVER_PID" 2>/dev/null || \
    { echo "FATAL: server process died" >&2; cat "$LOG_FILE" >&2 2>/dev/null || true; exit 1; }
done
