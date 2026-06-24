#!/usr/bin/env bash
set -euo pipefail
# Usage: test_ytdlp_integration.sh <ffmpeg-dir>
# ffmpeg-dir must contain ffmpeg and ffprobe

FFMPEG_DIR="$1"
[[ -x "$FFMPEG_DIR/ffmpeg" ]] || { echo "FATAL: $FFMPEG_DIR/ffmpeg not executable" >&2; exit 1; }
[[ -x "$FFMPEG_DIR/ffprobe" ]] || { echo "FATAL: $FFMPEG_DIR/ffprobe not executable" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
PASS=0; FAIL=0

for channel in stable nightly; do
  echo "=== Integration tests: $channel ==="
  TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/ytdlp-integration-${channel}.XXXXXX")"
  TMPBIN="$TMPROOT/bin"
  TMPOUT="$TMPROOT/output"
  mkdir -p "$TMPBIN" "$TMPOUT"

  SERVER_PIDS=()
  cleanup() {
    if (( ${#SERVER_PIDS[@]} > 0 )); then
      for pid in "${SERVER_PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
    fi
    rm -rf "$TMPROOT"
  }
  trap cleanup EXIT

  bash "$SCRIPT_DIR/download_pinned_ytdlp.sh" "$channel" "$TMPBIN"
  YT_DLP="$TMPBIN/yt-dlp"

  PORT_FILE="$TMPROOT/port"
  bash "$SCRIPT_DIR/start_fixture_server.sh" \
    --port-file "$PORT_FILE" \
    --directory "$FIXTURES_DIR"
  SERVER_PIDS+=("$(cat "${PORT_FILE}.pid")")
  HTTP_PORT="$(cat "$PORT_FILE")"

  # I1: download-sections (3s source → 0-1s, assert duration ≤ 1.5s)
  "$YT_DLP" --ignore-config --ffmpeg-location "$FFMPEG_DIR" \
    --download-sections "*00:00:00-00:00:01" \
    --verbose \
    -o "$TMPOUT/sections.mp4" \
    "http://127.0.0.1:${HTTP_PORT}/video_h264_aac.mp4" 2>&1 | tee "$TMPOUT/sections.log"
  if [[ -s "$TMPOUT/sections.mp4" ]]; then
    DURATION="$("$FFMPEG_DIR/ffprobe" -v error -show_entries format=duration \
      -of csv=p=0 "$TMPOUT/sections.mp4" 2>/dev/null)"
    if [[ -z "$DURATION" ]] || ! awk -v d="$DURATION" 'BEGIN{exit !(d+0 == d+0)}'; then
      echo "FAIL: I1 duration not numeric: '${DURATION:-empty}'" >&2; FAIL=$((FAIL + 1))
    elif awk -v d="$DURATION" 'BEGIN{exit !(d > 0 && d <= 1.5)}'; then
      if grep -qF "ffmpeg command line: $FFMPEG_DIR/ffmpeg" "$TMPOUT/sections.log"; then
        PASS=$((PASS + 1))
      else
        echo "FAIL: I1 sections did not use minimal ffmpeg from $FFMPEG_DIR" >&2; FAIL=$((FAIL + 1))
      fi
    else
      echo "FAIL: I1 sections duration ${DURATION}s > threshold 1.5s (requested 0-1s)" >&2; FAIL=$((FAIL + 1))
    fi
  else
    echo "FAIL: I1 sections output empty" >&2; FAIL=$((FAIL + 1))
  fi

  # I2: MP3 transcode
  "$YT_DLP" --ignore-config --ffmpeg-location "$FFMPEG_DIR" \
    -x --audio-format mp3 \
    -o "$TMPOUT/mp3.%(ext)s" \
    "http://127.0.0.1:${HTTP_PORT}/audio_aac.m4a"
  if "$FFMPEG_DIR/ffprobe" -show_streams "$TMPOUT"/mp3.* 2>/dev/null | grep -q "codec_name=mp3"; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: I2 MP3 output not valid" >&2; FAIL=$((FAIL + 1))
  fi

  # I3: HLS — ffmpeg downloader + log assertion
  "$YT_DLP" --ignore-config --ffmpeg-location "$FFMPEG_DIR" \
    --downloader m3u8:ffmpeg \
    --verbose \
    -o "$TMPOUT/hls.mp4" \
    "http://127.0.0.1:${HTTP_PORT}/hls/playlist.m3u8" 2>&1 | tee "$TMPOUT/hls.log"
  if [[ -s "$TMPOUT/hls.mp4" ]]; then
    if grep -qF "ffmpeg command line: $FFMPEG_DIR/ffmpeg" "$TMPOUT/hls.log"; then
      PASS=$((PASS + 1))
    else
      echo "FAIL: I3 HLS did not invoke minimal ffmpeg (expected 'ffmpeg command line: $FFMPEG_DIR/ffmpeg' in log)" >&2
      FAIL=$((FAIL + 1))
    fi
  else
    echo "FAIL: I3 HLS output empty" >&2; FAIL=$((FAIL + 1))
  fi

  if (( ${#SERVER_PIDS[@]} > 0 )); then
    for pid in "${SERVER_PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
  fi
  SERVER_PIDS=()
  rm -rf "$TMPROOT"
done

echo "=== Integration results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || { echo "FATAL: integration tests failed" >&2; exit 1; }
