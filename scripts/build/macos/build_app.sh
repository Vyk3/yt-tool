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

# Download the yt-dlp standalone macOS binary (universal, no Python required by the binary itself).
# This binary is bundled into the .app so users don't need yt-dlp installed separately.
YTDLP_BIN="$PROJECT_DIR/vendor/bin/yt-dlp"
mkdir -p "$PROJECT_DIR/vendor/bin"
if [[ -n "$CLEAN_FLAG" || ! -x "$YTDLP_BIN" ]]; then
  echo "Downloading yt-dlp macOS binary..."
  curl --fail --location --progress-bar \
    "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos" \
    -o "$YTDLP_BIN"
  chmod +x "$YTDLP_BIN"
  echo "yt-dlp binary: $YTDLP_BIN"
else
  echo "yt-dlp binary already present: $YTDLP_BIN"
fi

"$PYTHON" -m PyInstaller \
  --noconfirm \
  $CLEAN_FLAG \
  "$PROJECT_DIR/yt-tool.spec"

echo "Built app: $PROJECT_DIR/dist/$APP_NAME.app"

# Ad-hoc codesign — resolves "app is damaged" Gatekeeper error without a paid certificate.
# Users will still see "unverified developer" on first launch; right-click → Open to proceed.
codesign --force --deep --sign - "$PROJECT_DIR/dist/$APP_NAME.app"
echo "Codesigned (ad-hoc): $APP_NAME.app"

# Package as DMG for distribution.
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$PROJECT_DIR/dist/$APP_NAME.app" \
  -ov -format UDZO \
  "$PROJECT_DIR/dist/$APP_NAME-macOS.dmg"
echo "DMG: $PROJECT_DIR/dist/$APP_NAME-macOS.dmg"
