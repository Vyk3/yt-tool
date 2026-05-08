#!/usr/bin/env zsh
# Install development binaries into swift/YTTool/Resources/Binaries/.
#
# FOR DEVELOPMENT AND LOCAL TESTING ONLY.
# Do NOT use this script in CI or release builds.
# Production builds must use prepare_binaries.py with pinned URLs and SHA256.
#
# Usage:
#   scripts/build/swift/dev_install_binaries.sh [--force] [--channel stable|nightly] [--ytdlp-path /path/to/yt-dlp]
#
# Behavior:
# - yt-dlp: download the pinned zipapp and create a wrapper using system python3
# - ffmpeg/ffprobe: generate wrappers to local PATH tools (typically Homebrew)

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
      echo "Usage: $0 [--force] [--channel stable|nightly] [--ytdlp-path /path/to/yt-dlp]"
      echo "Installs yt-dlp zipapp plus ffmpeg/ffprobe into $BINARIES_DIR."
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

set_ytdlp_channel_vars "$CHANNEL"

echo "=== dev_install_binaries (DEV ONLY, channel: $CHANNEL) ==="

read_ytdlp_version() {
  local binary_path="$1"
  local version
  version="$("$binary_path" --version 2>/dev/null | head -n 1 | tr -d '\r')" || return 1
  [[ -n "$version" ]] || return 1
  echo "$version"
}

write_ytdlp_wrapper() {
  local dst="$1"
  cat > "$dst" <<'WRAPPER'
#!/bin/sh
DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON="$DIR/../Python/bin/python3.12"
if [ -x "$PYTHON" ]; then
    exec "$PYTHON" "$DIR/yt-dlp-zipapp" "$@"
else
    exec python3 "$DIR/yt-dlp-zipapp" "$@"
fi
WRAPPER
  chmod +x "$dst"
}

install_ytdlp() {
  local zipapp_dst="$BINARIES_DIR/yt-dlp-zipapp"
  local wrapper_dst="$BINARIES_DIR/yt-dlp"

  if [[ -z "${YTDLP_URL:-}" ]]; then
    echo "ERROR: YTDLP_URL is empty in pinned_versions.sh" >&2
    return 1
  fi

  if [[ "$FORCE" -eq 0 && -f "$zipapp_dst" && -x "$wrapper_dst" ]]; then
    local current_version
    current_version="$(read_ytdlp_version "$wrapper_dst" || true)"
    if [[ "$current_version" == "$YTDLP_VERSION" ]]; then
      echo "yt-dlp already present: $zipapp_dst (zipapp, channel: $CHANNEL, version: $current_version)"
      return 0
    fi
    echo "yt-dlp version mismatch (have: ${current_version:-unknown}, want: $YTDLP_VERSION); reinstalling for channel $CHANNEL"
  fi

  if [[ -n "$YTDLP_LOCAL_PATH" ]]; then
    if [[ ! -f "$YTDLP_LOCAL_PATH" ]]; then
      echo "ERROR: --ytdlp-path does not exist: $YTDLP_LOCAL_PATH" >&2
      return 1
    fi
    cp "$YTDLP_LOCAL_PATH" "$zipapp_dst"
    chmod +x "$zipapp_dst"
  else
    local tmp
    tmp="$(mktemp)"

    if ! curl -fsSL -o "$tmp" "$YTDLP_URL"; then
      rm -f "$tmp"
      echo "ERROR: failed to download yt-dlp from $YTDLP_URL" >&2
      echo "Hint: download the yt-dlp zipapp in a browser, then rerun with --ytdlp-path /path/to/yt-dlp" >&2
      return 1
    fi

    if [[ -n "${YTDLP_SHA256:-}" ]]; then
      local actual_sha
      actual_sha="$(shasum -a 256 "$tmp" | cut -d' ' -f1)"
      if [[ "$actual_sha" != "$YTDLP_SHA256" ]]; then
        rm -f "$tmp"
        echo "ERROR: yt-dlp SHA256 mismatch" >&2
        echo "  expected: $YTDLP_SHA256" >&2
        echo "  actual:   $actual_sha" >&2
        return 1
      fi
      echo "  SHA256 verified: $actual_sha"
    fi

    mv "$tmp" "$zipapp_dst"
    chmod +x "$zipapp_dst"
  fi

  write_ytdlp_wrapper "$wrapper_dst"

  local installed_version
  installed_version="$(read_ytdlp_version "$wrapper_dst" || echo unknown)"
  echo "yt-dlp  →  $zipapp_dst  (zipapp, channel: $CHANNEL, version: $installed_version)"
  echo "        →  $wrapper_dst  (wrapper, sha256=$(shasum -a 256 "$wrapper_dst" | cut -d' ' -f1))"
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
