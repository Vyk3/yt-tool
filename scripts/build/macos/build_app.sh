#!/bin/zsh
# Build macOS .app with PyInstaller using the unified app entry.
# Usage:
#   scripts/build/macos/build_app.sh [--clean] [--name APP_NAME] [--with-ffmpeg]
#                                   [--codesign-identity IDENTITY] [--ffmpeg-url URL]
#                                   [--ffmpeg-sha256 HEX] [--ffprobe-url URL]
#                                   [--ffprobe-sha256 HEX]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

APP_NAME="yt-tool"
CLEAN_FLAG=""
WITH_FFMPEG=0
CODESIGN_IDENTITY="${YT_TOOL_CODESIGN_IDENTITY:--}"
FFMPEG_ARCHIVE_URL="${YT_TOOL_FFMPEG_MACOS_URL:-}"
FFMPEG_ARCHIVE_SHA256="${YT_TOOL_FFMPEG_MACOS_SHA256:-}"
FFPROBE_ARCHIVE_URL="${YT_TOOL_FFPROBE_MACOS_URL:-}"
FFPROBE_ARCHIVE_SHA256="${YT_TOOL_FFPROBE_MACOS_SHA256:-}"

usage() {
  cat <<EOF
Usage: $0 [--clean] [--name APP_NAME] [--with-ffmpeg]
          [--codesign-identity IDENTITY] [--ffmpeg-url URL]
          [--ffmpeg-sha256 HEX] [--ffprobe-url URL]
          [--ffprobe-sha256 HEX]

Options:
  --clean                     Run PyInstaller with --clean and refresh bundled binaries.
  --name APP_NAME             App name (default: yt-tool).
  --with-ffmpeg               Download ffmpeg/ffprobe and bundle into app.
  --codesign-identity VALUE   codesign identity (default: '-' for ad-hoc).
                              Can also be set by YT_TOOL_CODESIGN_IDENTITY.
  --ffmpeg-url URL            Override ffmpeg archive URL.
                              Can also be set by YT_TOOL_FFMPEG_MACOS_URL.
  --ffmpeg-sha256 HEX         Expected SHA256 for ffmpeg archive.
                              Can also be set by YT_TOOL_FFMPEG_MACOS_SHA256.
  --ffprobe-url URL           Override ffprobe archive URL.
                              Can also be set by YT_TOOL_FFPROBE_MACOS_URL.
  --ffprobe-sha256 HEX        Expected SHA256 for ffprobe archive.
                              Can also be set by YT_TOOL_FFPROBE_MACOS_SHA256.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)
      CLEAN_FLAG="--clean"
      shift
      ;;
    --name)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Missing value for --name" >&2
        usage >&2
        exit 2
      fi
      APP_NAME="$2"
      shift 2
      ;;
    --with-ffmpeg)
      WITH_FFMPEG=1
      shift
      ;;
    --codesign-identity)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Missing value for --codesign-identity" >&2
        usage >&2
        exit 2
      fi
      CODESIGN_IDENTITY="$2"
      shift 2
      ;;
    --ffmpeg-url)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Missing value for --ffmpeg-url" >&2
        usage >&2
        exit 2
      fi
      FFMPEG_ARCHIVE_URL="$2"
      shift 2
      ;;
    --ffmpeg-sha256)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Missing value for --ffmpeg-sha256" >&2
        usage >&2
        exit 2
      fi
      FFMPEG_ARCHIVE_SHA256="$2"
      shift 2
      ;;
    --ffprobe-url)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Missing value for --ffprobe-url" >&2
        usage >&2
        exit 2
      fi
      FFPROBE_ARCHIVE_URL="$2"
      shift 2
      ;;
    --ffprobe-sha256)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Missing value for --ffprobe-sha256" >&2
        usage >&2
        exit 2
      fi
      FFPROBE_ARCHIVE_SHA256="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
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

VENDOR_BIN_DIR="$PROJECT_DIR/vendor/bin"
mkdir -p "$VENDOR_BIN_DIR"
PREPARE_FFMPEG_PY="$PROJECT_DIR/scripts/build/common/prepare_ffmpeg.py"

if [[ "$WITH_FFMPEG" -eq 1 ]]; then
  PREPARE_ARGS=(
    "$PREPARE_FFMPEG_PY"
    --platform macos
    --vendor-bin-dir "$VENDOR_BIN_DIR"
    --ffmpeg-url "$FFMPEG_ARCHIVE_URL"
    --ffmpeg-sha256 "$FFMPEG_ARCHIVE_SHA256"
    --ffprobe-url "$FFPROBE_ARCHIVE_URL"
    --ffprobe-sha256 "$FFPROBE_ARCHIVE_SHA256"
  )
  if [[ -n "$CLEAN_FLAG" ]]; then
    PREPARE_ARGS+=(--clean)
  fi
  "$PYTHON" "${PREPARE_ARGS[@]}"
fi

"$PYTHON" -m PyInstaller \
  --noconfirm \
  $CLEAN_FLAG \
  "$PROJECT_DIR/yt-tool.spec"

echo "Built app: $PROJECT_DIR/dist/$APP_NAME.app"

# Default ad-hoc codesign resolves "app is damaged" Gatekeeper error without a paid certificate.
# You can pass --codesign-identity "Developer ID Application: ..." for signed distribution builds.
codesign --force --deep --sign "$CODESIGN_IDENTITY" "$PROJECT_DIR/dist/$APP_NAME.app"
if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
  echo "Codesigned (ad-hoc): $APP_NAME.app"
else
  echo "Codesigned with identity '$CODESIGN_IDENTITY': $APP_NAME.app"
fi

# Package as DMG for distribution.
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$PROJECT_DIR/dist/$APP_NAME.app" \
  -ov -format UDZO \
  "$PROJECT_DIR/dist/$APP_NAME-macOS.dmg"
echo "DMG: $PROJECT_DIR/dist/$APP_NAME-macOS.dmg"
