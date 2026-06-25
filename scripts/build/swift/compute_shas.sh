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

compute_zip_member() {
    local label="$1"
    local url="$2"
    local member="$3"
    local tmp
    tmp="$(mktemp)"
    echo "Downloading $label..."
    curl -fsSL -o "$tmp" "$url"
    local sha
    sha="$(unzip -p "$tmp" "$member" | shasum -a 256 | cut -d' ' -f1)"
    echo "${label}_SHA256=\"${sha}\""
    rm -f "$tmp"
}

compute "YTDLP" "$YTDLP_URL"

# Single ZIP → 3 SHAs: archive + ffmpeg member + ffprobe member
echo "Downloading ffmpeg archive..."
FFMPEG_TMP="$(mktemp)"
curl -fsSL -o "$FFMPEG_TMP" "$FFMPEG_URL"
echo "FFMPEG_ARCHIVE_SHA256=\"$(shasum -a 256 "$FFMPEG_TMP" | cut -d' ' -f1)\""
echo "FFMPEG_BIN_SHA256=\"$(unzip -p "$FFMPEG_TMP" ffmpeg | shasum -a 256 | cut -d' ' -f1)\""
echo "FFPROBE_BIN_SHA256=\"$(unzip -p "$FFMPEG_TMP" ffprobe | shasum -a 256 | cut -d' ' -f1)\""
rm -f "$FFMPEG_TMP"
