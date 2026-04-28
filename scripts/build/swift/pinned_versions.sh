#!/usr/bin/env zsh
# Pinned binary versions for YTTool release builds.
#
# Update BOTH the URL and SHA256 whenever upgrading a dependency.
# Run compute_shas.sh to recalculate checksums after changing a URL.
#
# yt-dlp standalone channels (macOS universal binary, NOT the Homebrew Python
# wrapper):
#   stable:  https://github.com/yt-dlp/yt-dlp/releases
#   nightly: https://github.com/yt-dlp/yt-dlp-nightly-builds/releases

YTDLP_STABLE_VERSION="2026.03.17"
YTDLP_STABLE_URL="https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_STABLE_VERSION}/yt-dlp_macos"
YTDLP_STABLE_SHA256="e80c47b3ce712acee51d5e3d4eace2d181b44d38f1942c3a32e3c7ff53cd9ed5"

YTDLP_NIGHTLY_VERSION="2026.04.10.235301"
YTDLP_NIGHTLY_URL="https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/download/${YTDLP_NIGHTLY_VERSION}/yt-dlp_macos"
YTDLP_NIGHTLY_SHA256="4cdff585ace431c72fd28b70e5a375805948e2b80585efd261797be84f76af82"

# Backward-compatible defaults: scripts should prefer set_ytdlp_channel_vars().
YTDLP_VERSION="$YTDLP_STABLE_VERSION"
YTDLP_URL="$YTDLP_STABLE_URL"
YTDLP_SHA256="$YTDLP_STABLE_SHA256"

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
# For now, dev mode copies local ffmpeg/ffprobe binaries from PATH (typically
# Homebrew on Apple Silicon). Release mode requires these to be filled in.

FFMPEG_VERSION="7.1.1"
# Intel static (evermeet.cx); replace with arm64 source for release.
FFMPEG_URL="https://evermeet.cx/ffmpeg/ffmpeg-${FFMPEG_VERSION}.zip"
FFMPEG_SHA256=""

FFPROBE_URL="https://evermeet.cx/ffmpeg/ffprobe-${FFMPEG_VERSION}.zip"
FFPROBE_SHA256=""

normalize_ytdlp_channel() {
  local channel="${1:-stable}"
  case "$channel" in
    stable|nightly) echo "$channel" ;;
    *)
      echo "ERROR: unsupported yt-dlp channel: $channel" >&2
      return 2 ;;
  esac
}

set_ytdlp_channel_vars() {
  local channel
  channel="$(normalize_ytdlp_channel "${1:-stable}")" || return $?

  case "$channel" in
    stable)
      YTDLP_VERSION="$YTDLP_STABLE_VERSION"
      YTDLP_URL="$YTDLP_STABLE_URL"
      YTDLP_SHA256="$YTDLP_STABLE_SHA256"
      ;;
    nightly)
      YTDLP_VERSION="$YTDLP_NIGHTLY_VERSION"
      YTDLP_URL="$YTDLP_NIGHTLY_URL"
      YTDLP_SHA256="$YTDLP_NIGHTLY_SHA256"
      ;;
  esac
}
