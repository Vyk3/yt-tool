#!/usr/bin/env zsh
# Copy locally installed Homebrew binaries into swift/YTTool/Resources/Binaries/.
#
# FOR DEVELOPMENT AND LOCAL TESTING ONLY.
# Do NOT use this script in CI or release builds.
# Production builds must use prepare_binaries.py with pinned URLs and SHA256.
#
# Usage:
#   scripts/build/swift/dev_install_binaries.sh [--force]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BINARIES_DIR="$PROJECT_DIR/swift/YTTool/Resources/Binaries"
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--force]"
      echo "Copies yt-dlp, ffmpeg, ffprobe from Homebrew into $BINARIES_DIR."
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

echo "=== dev_install_binaries (DEV ONLY) ==="

copy_tool() {
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

  cp "$src" "$dst"
  chmod +x "$dst"
  echo "$name  →  $dst  ($(shasum -a 256 "$dst" | cut -d' ' -f1))"
}

mkdir -p "$BINARIES_DIR"
copy_tool yt-dlp
copy_tool ffmpeg
copy_tool ffprobe

echo ""
echo "Done. Binaries are for local development only — do not commit them."
