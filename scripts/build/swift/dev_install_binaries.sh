#!/usr/bin/env zsh
# Install development binaries into swift/YTTool/Resources/Binaries/.
#
# FOR DEVELOPMENT AND LOCAL TESTING ONLY.
# Do NOT use this script in CI or release builds.
# Production builds must use prepare_binaries.py with pinned URLs and SHA256.
#
# Usage:
#   scripts/build/swift/dev_install_binaries.sh [--force] [--channel stable|nightly] [--ytdlp-path /path/to/yt-dlp_macos]
#
# Behavior:
# - yt-dlp: download the pinned standalone macOS binary from pinned_versions.sh
# - ffmpeg/ffprobe: generate wrappers to local PATH tools (typically Homebrew)
#
# This avoids bundling Homebrew's Python shim for yt-dlp, which is fragile and
# can behave differently from the standalone binary used in release packaging.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BINARIES_DIR="$PROJECT_DIR/swift/YTTool/Resources/Binaries"
FORCE=0
CHANNEL="stable"
YTDLP_LOCAL_PATH=""
source "$SCRIPT_DIR/pinned_versions.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --channel) CHANNEL="$2"; shift 2 ;;
    --ytdlp-path) YTDLP_LOCAL_PATH="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--force] [--channel stable|nightly] [--ytdlp-path /path/to/yt-dlp_macos]"
      echo "Installs standalone yt-dlp plus ffmpeg/ffprobe into $BINARIES_DIR."
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

set_ytdlp_channel_vars "$CHANNEL"

echo "=== dev_install_binaries (DEV ONLY, channel: $CHANNEL) ==="

install_ytdlp() {
  local dst="$BINARIES_DIR/yt-dlp"

  if [[ -z "${YTDLP_URL:-}" ]]; then
    echo "ERROR: YTDLP_URL is empty in pinned_versions.sh" >&2
    return 1
  fi

  if [[ "$FORCE" -eq 0 && -x "$dst" ]]; then
    if ! head -n 1 "$dst" | grep -q '^#!'; then
      echo "yt-dlp already present: $dst (standalone binary, channel: $CHANNEL)"
      return 0
    fi
    echo "yt-dlp present but looks like a script shim; replacing with standalone binary"
  fi

  if [[ -n "$YTDLP_LOCAL_PATH" ]]; then
    if [[ ! -f "$YTDLP_LOCAL_PATH" ]]; then
      echo "ERROR: --ytdlp-path does not exist: $YTDLP_LOCAL_PATH" >&2
      return 1
    fi
    cp "$YTDLP_LOCAL_PATH" "$dst"
    chmod +x "$dst"
    echo "yt-dlp  →  $dst  (from local file: $YTDLP_LOCAL_PATH, channel: $CHANNEL)"
    echo "          sha256=$(shasum -a 256 "$dst" | cut -d' ' -f1)"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"

  if ! curl -fsSL -o "$tmp" "$YTDLP_URL"; then
    rm -f "$tmp"
    echo "ERROR: failed to download yt-dlp from $YTDLP_URL" >&2
    echo "Hint: download yt-dlp_macos in a browser, then rerun with --ytdlp-path /path/to/yt-dlp_macos" >&2
    return 1
  fi

  mv "$tmp" "$dst"
  chmod +x "$dst"
  echo "yt-dlp  →  $dst  (channel: $CHANNEL, $(shasum -a 256 "$dst" | cut -d' ' -f1))"
}

install_path_tool_wrapper() {
  local name="$1"
  local src
  src="$(command -v "$name" 2>/dev/null || true)"
  local dst="$BINARIES_DIR/$name"

  if [[ -z "$src" ]]; then
    echo "ERROR: $name not found in PATH. Install with: brew install $name" >&2
    return 1
  fi

  if [[ "$FORCE" -eq 0 && -x "$dst" ]]; then
    echo "$name already present: $dst (use --force to overwrite)"
    return 0
  fi

  rm -f "$dst"
  cat > "$dst" <<EOF
#!/bin/sh
exec "$src" "\$@"
EOF
  chmod +x "$dst"
  echo "$name  →  $dst  (wrapper to $src, $(shasum -a 256 "$dst" | cut -d' ' -f1))"
}

mkdir -p "$BINARIES_DIR"
install_ytdlp
install_path_tool_wrapper ffmpeg
install_path_tool_wrapper ffprobe

echo ""
echo "Done. Binaries are for local development only — do not commit them."
