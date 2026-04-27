#!/usr/bin/env zsh
# Pinned binary versions for YTTool release builds.
#
# Update BOTH the URL and SHA256 whenever upgrading a dependency.
# Run compute_shas.sh to recalculate checksums after changing a URL.
#
# yt-dlp standalone (macOS universal binary, NOT the Homebrew Python wrapper):
#   https://github.com/yt-dlp/yt-dlp/releases

YTDLP_VERSION="2026.03.17"
YTDLP_URL="https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_VERSION}/yt-dlp_macos"
# SHA256: run `scripts/build/swift/compute_shas.sh` to compute and fill in.
YTDLP_SHA256=""

# ffmpeg/ffprobe static macOS arm64 (from evermeet.cx — Intel — or use
# BtbN/FFmpeg-Builds for universal/arm64).
# Adjust URL to match the correct architecture for your release target.
#
# For arm64 (Apple Silicon):
#   https://github.com/BtbN/FFmpeg-Builds/releases — look for
#   "ffmpeg-master-latest-macos64-gpl.zip" (Intel) or similar.
#   evermeet.cx builds are Intel only; for Apple Silicon prefer homebrew-bottled
#   or BtbN builds until an arm64-static source is pinned here.
#
# For now, dev mode uses local Homebrew binaries (arm64). Release mode
# requires these to be filled in.

FFMPEG_VERSION="7.1.1"
# Intel static (evermeet.cx); replace with arm64 source for release.
FFMPEG_URL="https://evermeet.cx/ffmpeg/ffmpeg-${FFMPEG_VERSION}.zip"
FFMPEG_SHA256=""

FFPROBE_URL="https://evermeet.cx/ffmpeg/ffprobe-${FFMPEG_VERSION}.zip"
FFPROBE_SHA256=""
