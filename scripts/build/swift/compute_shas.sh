#!/usr/bin/env zsh
# Download each pinned binary and print its SHA256.
# Paste the output into pinned_versions.sh.
#
# Usage: scripts/build/swift/compute_shas.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/pinned_versions.sh"

compute() {
    local label="$1"
    local url="$2"
    local tmp
    tmp="$(mktemp)"
    echo "Downloading $label..."
    curl -fsSL -o "$tmp" "$url"
    local sha
    sha="$(shasum -a 256 "$tmp" | cut -d' ' -f1)"
    echo "${label}_SHA256=\"${sha}\""
    rm -f "$tmp"
}

compute "YTDLP"   "$YTDLP_URL"
compute "FFMPEG"  "$FFMPEG_URL"
compute "FFPROBE" "$FFPROBE_URL"
