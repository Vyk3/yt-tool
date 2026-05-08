#!/usr/bin/env zsh
# Pinned binary versions for YTTool release builds.
#
# Update BOTH the URL and SHA256 whenever upgrading a dependency.
# Run compute_shas.sh to recalculate checksums after changing a URL.
#
# yt-dlp zipapp (cross-platform Python zipapp, invoked via embedded Python
# runtime instead of the old PyInstaller standalone binary):
#   stable:  https://github.com/yt-dlp/yt-dlp/releases
#   nightly: https://github.com/yt-dlp/yt-dlp-nightly-builds/releases

YTDLP_STABLE_VERSION="2026.03.17"
YTDLP_STABLE_URL="https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_STABLE_VERSION}/yt-dlp"
YTDLP_STABLE_SHA256="3bda0968a01cde70d26720653003b28553c71be14dcb2e5f4c24e9921fdad745"

YTDLP_NIGHTLY_VERSION="2026.04.10.235301"
YTDLP_NIGHTLY_URL="https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/download/${YTDLP_NIGHTLY_VERSION}/yt-dlp"
YTDLP_NIGHTLY_SHA256="7298cfe6d4ee40c3440daf9a9b98a5367913a54a924fa0844640e79a1179419e"

# Embedded Python runtime (python-build-standalone, relocatable).
# Used in release builds to invoke the yt-dlp zipapp. Dev builds use system python3.
PYTHON_VERSION="3.12.13"
PYTHON_BUILD_TAG="20260504"
PYTHON_AARCH64_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PYTHON_BUILD_TAG}/cpython-${PYTHON_VERSION}%2B${PYTHON_BUILD_TAG}-aarch64-apple-darwin-install_only_stripped.tar.gz"
PYTHON_AARCH64_SHA256="dbba2cb07d0c5c1e641aefefe78c5706ff7a01e2c4d1de18e8447522af37431e"

# Backward-compatible defaults: scripts should prefer set_ytdlp_channel_vars().
YTDLP_VERSION="$YTDLP_STABLE_VERSION"
YTDLP_URL="$YTDLP_STABLE_URL"
YTDLP_SHA256="$YTDLP_STABLE_SHA256"

# ffmpeg/ffprobe static macOS builds.
#
# Current source: evermeet.cx — Intel (x86_64) only static builds.
# These run on Apple Silicon via Rosetta 2 (installed by default on all
# Apple Silicon Macs). build.sh will verify Rosetta is present before
# proceeding in release mode.
#
# To switch to native arm64 builds, pin a universal or arm64-native source
# (no ready-made public static arm64 macOS ffmpeg source is currently
# available from evermeet.cx or BtbN). Dev mode always copies local
# Homebrew binaries, which are arm64-native on Apple Silicon.

FFMPEG_VERSION="7.1.1"
FFMPEG_URL="https://evermeet.cx/ffmpeg/ffmpeg-${FFMPEG_VERSION}.zip"
FFMPEG_SHA256="8d7917c1cebd7a29e68c0a0a6cc4ecc3fe05c7fffed958636c7018b319afdda4"

FFPROBE_URL="https://evermeet.cx/ffmpeg/ffprobe-${FFMPEG_VERSION}.zip"
FFPROBE_SHA256="5a0a77d5e0c689f7b577788e286dd46b2c6120babd14301cce7a79fcfd3f7d28"

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
