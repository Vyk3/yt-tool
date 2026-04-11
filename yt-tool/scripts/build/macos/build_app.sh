#!/bin/zsh
# Build macOS .app with PyInstaller using the unified app entry.
# Usage:
#   scripts/build/macos/build_app.sh [--clean] [--name APP_NAME]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

APP_NAME="yt-tool"
CLEAN_FLAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)
      CLEAN_FLAG="--clean"
      shift
      ;;
    --name)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Missing value for --name" >&2
        echo "Usage: $0 [--clean] [--name APP_NAME]" >&2
        exit 2
      fi
      APP_NAME="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--clean] [--name APP_NAME]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -x "$PROJECT_DIR/.venv/bin/python3" ]]; then
  PYTHON="$PROJECT_DIR/.venv/bin/python3"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON="python3"
else
  echo "python3 not found" >&2
  exit 2
fi

if ! "$PYTHON" -c "import PyInstaller" >/dev/null 2>&1; then
  echo "PyInstaller is not installed in current environment." >&2
  echo "Install it with: $PYTHON -m pip install pyinstaller" >&2
  exit 2
fi

cd "$PROJECT_DIR"

"$PYTHON" -m PyInstaller \
  --noconfirm \
  $CLEAN_FLAG \
  --windowed \
  --name "$APP_NAME" \
  --paths "$PROJECT_DIR" \
  --paths "$PROJECT_DIR/vendor" \
  app/__main__.py

echo "Built app: $PROJECT_DIR/dist/$APP_NAME.app"
