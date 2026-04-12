#!/bin/zsh
# Build macOS .app with PyInstaller using the unified app entry.
# Usage:
#   scripts/build/macos/build_app.sh [--clean] [--name APP_NAME] [--with-ffmpeg]
#                                   [--codesign-identity IDENTITY] [--ffmpeg-url URL]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

APP_NAME="yt-tool"
CLEAN_FLAG=""
WITH_FFMPEG=0
CODESIGN_IDENTITY="${YT_TOOL_CODESIGN_IDENTITY:--}"
if [[ -n "${YT_TOOL_FFMPEG_MACOS_URL:-}" ]]; then
  FFMPEG_ARCHIVE_URL="$YT_TOOL_FFMPEG_MACOS_URL"
else
  # macOS builds are provided by evermeet; URL redirects to the latest ffmpeg zip.
  FFMPEG_ARCHIVE_URL="https://evermeet.cx/ffmpeg/getrelease/zip"
fi

usage() {
  cat <<EOF
Usage: $0 [--clean] [--name APP_NAME] [--with-ffmpeg]
          [--codesign-identity IDENTITY] [--ffmpeg-url URL]

Options:
  --clean                     Run PyInstaller with --clean and refresh bundled binaries.
  --name APP_NAME             App name (default: yt-tool).
  --with-ffmpeg               Download ffmpeg/ffprobe and bundle into app.
  --codesign-identity VALUE   codesign identity (default: '-' for ad-hoc).
                              Can also be set by YT_TOOL_CODESIGN_IDENTITY.
  --ffmpeg-url URL            Override ffmpeg archive URL.
                              Can also be set by YT_TOOL_FFMPEG_MACOS_URL.
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

# Download the yt-dlp standalone macOS binary (universal, no Python required by the binary itself).
# This binary is bundled into the .app so users don't need yt-dlp installed separately.
YTDLP_BIN="$PROJECT_DIR/vendor/bin/yt-dlp"
VENDOR_BIN_DIR="$PROJECT_DIR/vendor/bin"
mkdir -p "$VENDOR_BIN_DIR"
if [[ -n "$CLEAN_FLAG" || ! -x "$YTDLP_BIN" ]]; then
  echo "Downloading yt-dlp macOS binary..."
  curl --fail --location --progress-bar \
    --retry 5 --retry-delay 2 --retry-all-errors \
    "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos" \
  -o "$YTDLP_BIN"
  chmod +x "$YTDLP_BIN"
  echo "yt-dlp binary: $YTDLP_BIN"
else
  echo "yt-dlp binary already present: $YTDLP_BIN"
fi

if [[ "$WITH_FFMPEG" -eq 1 ]]; then
  if ! command -v unzip >/dev/null 2>&1; then
    echo "unzip not found; required for --with-ffmpeg." >&2
    echo "Install it via Xcode Command Line Tools or your package manager." >&2
    exit 2
  fi

  FFMPEG_BIN="$VENDOR_BIN_DIR/ffmpeg"
  FFPROBE_BIN="$VENDOR_BIN_DIR/ffprobe"
  if [[ -n "$CLEAN_FLAG" || ! -x "$FFMPEG_BIN" || ! -x "$FFPROBE_BIN" ]]; then
    (
      tmp_dir="$(mktemp -d)"
      trap 'rm -rf "$tmp_dir"' EXIT
      archive_path="$tmp_dir/ffmpeg-macos.zip"
      echo "Downloading ffmpeg archive..."
      curl --fail --location --progress-bar \
        --retry 5 --retry-delay 2 --retry-all-errors \
        "$FFMPEG_ARCHIVE_URL" -o "$archive_path"
      # Support both archive layouts:
      # 1) FFmpeg-Builds style: */bin/ffmpeg + */bin/ffprobe
      # 2) evermeet style: top-level "ffmpeg" only
      unzip -q -o -j "$archive_path" "*/bin/ffmpeg" -d "$VENDOR_BIN_DIR" || true
      unzip -q -o -j "$archive_path" "*/bin/ffprobe" -d "$VENDOR_BIN_DIR" || true
      unzip -q -o -j "$archive_path" "ffmpeg" -d "$VENDOR_BIN_DIR" || true
      unzip -q -o -j "$archive_path" "ffprobe" -d "$VENDOR_BIN_DIR" || true
    )
    if [[ ! -f "$FFMPEG_BIN" ]]; then
      echo "ffmpeg archive does not contain ffmpeg: $FFMPEG_ARCHIVE_URL" >&2
      exit 2
    fi
    if [[ ! -f "$FFPROBE_BIN" ]] && command -v ffprobe >/dev/null 2>&1; then
      cp "$(command -v ffprobe)" "$FFPROBE_BIN"
    fi
    chmod +x "$FFMPEG_BIN"
    if [[ -f "$FFPROBE_BIN" ]]; then
      chmod +x "$FFPROBE_BIN"
    fi
    echo "ffmpeg binary: $FFMPEG_BIN"
    if [[ -f "$FFPROBE_BIN" ]]; then
      echo "ffprobe binary: $FFPROBE_BIN"
    else
      echo "ffprobe binary not bundled (optional)"
    fi
  else
    echo "ffmpeg binaries already present: $FFMPEG_BIN / $FFPROBE_BIN"
  fi
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
