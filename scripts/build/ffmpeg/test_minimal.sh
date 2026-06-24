#!/usr/bin/env bash
set -euo pipefail
# Usage: test_minimal.sh <ffmpeg-path> <ffprobe-path>
# Runs offline fixture tests against the minimal ffmpeg/ffprobe build.

FFMPEG="$1"
FFPROBE="$2"
[[ -x "$FFMPEG" ]]  || { echo "FATAL: $FFMPEG not executable" >&2; exit 1; }
[[ -x "$FFPROBE" ]] || { echo "FATAL: $FFPROBE not executable" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

# --- fixture SHA inventory gate ---
(
  cd "$FIXTURES_DIR"
  shasum -a 256 -c SHA256SUMS || { echo "FATAL: fixture SHA mismatch" >&2; exit 1; }
  UNLISTED="$(comm -23 \
    <(find . -type f ! -name 'GENERATION.md' ! -name 'SHA256SUMS' ! -name '.*' | sed 's|^\./||' | LC_ALL=C sort) \
    <(sed 's/^[0-9a-f]*  //' SHA256SUMS | LC_ALL=C sort))"
  [[ -z "$UNLISTED" ]] || { echo "FATAL: unlisted fixtures: $UNLISTED" >&2; exit 1; }
) || exit 1

TEST_TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/ffmpeg-test.XXXXXX")"
SERVER_PIDS=()
cleanup_servers() {
  if (( ${#SERVER_PIDS[@]} > 0 )); then
    for pid in "${SERVER_PIDS[@]}"; do
      kill "$pid" 2>/dev/null || true
    done
  fi
  rm -rf "$TEST_TMPROOT"
}
trap cleanup_servers EXIT

PASS=0; FAIL=0; TOTAL=0

run_test() {
  local num="$1" desc="$2"
  TOTAL=$((TOTAL + 1))
  echo "--- #$num: $desc ---"
}

pass() { PASS=$((PASS + 1)); echo "PASS"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1" >&2; }

# === #1 MP4 stream-copy ===
run_test 1 "MP4 stream-copy"
"$FFMPEG" -y -i "$FIXTURES_DIR/video_h264_aac.mp4" -c copy "$TEST_TMPROOT/t01.mp4" 2>/dev/null
T01_PROBE="$("$FFPROBE" -of json -show_streams "$TEST_TMPROOT/t01.mp4" 2>/dev/null)" || true
if echo "$T01_PROBE" | grep -q '"codec_name": "h264"' && \
   echo "$T01_PROBE" | grep -q '"codec_name": "aac"'; then
  pass
else
  fail "missing h264 or aac stream"
fi

# === #2 MKV stream-copy ===
run_test 2 "MKV stream-copy"
"$FFMPEG" -y -i "$FIXTURES_DIR/video_h264_aac.mp4" -c copy "$TEST_TMPROOT/t02.mkv" 2>/dev/null
if "$FFPROBE" -show_format "$TEST_TMPROOT/t02.mkv" 2>/dev/null | grep -q "format_name=matroska"; then
  pass
else
  fail "format not matroska"
fi

# === #3 WebM stream-copy ===
run_test 3 "WebM stream-copy"
"$FFMPEG" -y -i "$FIXTURES_DIR/video_vp9_opus.webm" -c copy "$TEST_TMPROOT/t03.webm" 2>/dev/null
if "$FFPROBE" -show_format "$TEST_TMPROOT/t03.webm" 2>/dev/null | grep -q "format_name=matroska,webm"; then
  pass
else
  fail "format not matroska,webm"
fi

# === #4 MP3 transcode (AAC source) ===
run_test 4 "MP3 transcode (AAC source)"
"$FFMPEG" -y -i "$FIXTURES_DIR/audio_aac.m4a" -c:a libmp3lame "$TEST_TMPROOT/t04.mp3" 2>/dev/null
if "$FFPROBE" -show_streams "$TEST_TMPROOT/t04.mp3" 2>/dev/null | grep -q "codec_name=mp3"; then
  pass
else
  fail "codec not mp3"
fi

# === #5 M4A transcode ===
run_test 5 "M4A transcode"
"$FFMPEG" -y -i "$FIXTURES_DIR/audio_aac.m4a" -c:a aac "$TEST_TMPROOT/t05.m4a" 2>/dev/null
if "$FFPROBE" -show_streams "$TEST_TMPROOT/t05.m4a" 2>/dev/null | grep -q "codec_name=aac"; then
  pass
else
  fail "codec not aac"
fi

# === #6 WAV transcode ===
run_test 6 "WAV transcode"
"$FFMPEG" -y -i "$FIXTURES_DIR/audio_aac.m4a" -c:a pcm_s16le "$TEST_TMPROOT/t06.wav" 2>/dev/null
if "$FFPROBE" -show_streams "$TEST_TMPROOT/t06.wav" 2>/dev/null | grep -q "codec_name=pcm_s16le"; then
  pass
else
  fail "codec not pcm_s16le"
fi

# === #7 E-AC-3 → MP3 ===
run_test 7 "E-AC-3 → MP3"
"$FFMPEG" -y -i "$FIXTURES_DIR/audio_eac3.mp4" -c:a libmp3lame "$TEST_TMPROOT/t07.mp3" 2>/dev/null
if "$FFPROBE" -show_streams "$TEST_TMPROOT/t07.mp3" 2>/dev/null | grep -q "codec_name=mp3"; then
  pass
else
  fail "codec not mp3"
fi

# === #8 Thumbnail embed ===
run_test 8 "Thumbnail embed (JPEG)"
"$FFMPEG" -y -i "$FIXTURES_DIR/video_h264_aac.mp4" -i "$FIXTURES_DIR/thumb_jpeg.jpg" \
  -map 0 -map 1 -c copy -c:v:1 mjpeg -disposition:v:1 attached_pic \
  "$TEST_TMPROOT/t08.mp4" 2>/dev/null
if "$FFPROBE" -show_streams "$TEST_TMPROOT/t08.mp4" 2>/dev/null | grep -q "attached_pic=1"; then
  pass
else
  fail "no attached_pic stream"
fi

# === #9 Chapter injection ===
run_test 9 "Chapter injection"
"$FFMPEG" -y -i "$FIXTURES_DIR/video_h264_aac.mp4" -i "$FIXTURES_DIR/chapters.ffmetadata" \
  -map_metadata 1 -c copy "$TEST_TMPROOT/t09.mp4" 2>/dev/null
CHAPTER_COUNT="$("$FFPROBE" -show_chapters -of json "$TEST_TMPROOT/t09.mp4" 2>/dev/null | python3 -c 'import json,sys;print(len(json.load(sys.stdin).get("chapters",[])))')"
if [[ "$CHAPTER_COUNT" -ge 1 ]]; then
  pass
else
  fail "no chapters found"
fi

# === #10 ffprobe JSON ===
run_test 10 "ffprobe JSON output"
PROBE_OUT="$("$FFPROBE" -show_streams -show_format -of json "$FIXTURES_DIR/video_h264_aac.mp4" 2>/dev/null)"
if echo "$PROBE_OUT" | python3 -c 'import json,sys;d=json.load(sys.stdin);assert "streams" in d' 2>/dev/null && \
   echo "$PROBE_OUT" | grep -q '"codec_name"'; then
  pass
else
  fail "JSON parse failed or no codec_name"
fi

# === #11 mpegts ===
run_test 11 "mpegts demux"
"$FFMPEG" -y -i "$FIXTURES_DIR/segment.ts" -c copy "$TEST_TMPROOT/t11.mp4" 2>/dev/null
if "$FFPROBE" -show_format "$TEST_TMPROOT/t11.mp4" 2>/dev/null | grep -q "format_name"; then
  pass
else
  fail "output not probeable"
fi

# === #12 Segment simulation (download-sections) ===
run_test 12 "Segment simulation"
"$FFMPEG" -y -ss 0 -t 1 -i "$FIXTURES_DIR/video_h264_aac.mp4" -c copy "$TEST_TMPROOT/t12.mp4" 2>/dev/null
if "$FFPROBE" -show_format "$TEST_TMPROOT/t12.mp4" 2>/dev/null | grep -q "format_name"; then
  pass
else
  fail "output not probeable"
fi

# === #13 setts BSF ===
run_test 13 "setts BSF"
"$FFMPEG" -y -i "$FIXTURES_DIR/video_h264_aac.mp4" -bsf:v setts=pts=PTS -c copy "$TEST_TMPROOT/t13.mp4" 2>/dev/null
if "$FFPROBE" -show_streams "$TEST_TMPROOT/t13.mp4" 2>/dev/null | grep -q "codec_name=h264"; then
  pass
else
  fail "setts output missing h264"
fi

# === #14 Encrypted HLS ===
run_test 14 "Encrypted HLS"
"$FFMPEG" -y -allowed_extensions ALL -i "$FIXTURES_DIR/hls/playlist.m3u8" -c copy "$TEST_TMPROOT/t14.mp4" 2>/dev/null
if "$FFPROBE" -show_format "$TEST_TMPROOT/t14.mp4" 2>/dev/null | grep -q "format_name"; then
  pass
else
  fail "HLS output not probeable"
fi

# === #15 Local HTTP ===
run_test 15 "Local HTTP"
HTTP_PORT_FILE="$TEST_TMPROOT/http_port"
bash "$SCRIPT_DIR/start_fixture_server.sh" \
  --port-file "$HTTP_PORT_FILE" \
  --directory "$FIXTURES_DIR"
SERVER_PIDS+=("$(cat "${HTTP_PORT_FILE}.pid")")
HTTP_PORT="$(cat "$HTTP_PORT_FILE")"

"$FFMPEG" -y -i "http://127.0.0.1:${HTTP_PORT}/video_h264_aac.mp4" -c copy "$TEST_TMPROOT/t15.mp4" 2>/dev/null
if "$FFPROBE" -show_format "$TEST_TMPROOT/t15.mp4" 2>/dev/null | grep -q "format_name=mov"; then
  pass
else
  fail "HTTP stream not mov format"
fi

# === #16 HTTPS smoke ===
run_test 16 "HTTPS smoke"
openssl req -x509 -newkey rsa:2048 -keyout "$TEST_TMPROOT/test-key.pem" -out "$TEST_TMPROOT/test-cert.pem" \
  -days 1 -nodes -subj '/CN=localhost' 2>/dev/null

HTTPS_PORT_FILE="$TEST_TMPROOT/https_port"
bash "$SCRIPT_DIR/start_fixture_server.sh" \
  --https --cert "$TEST_TMPROOT/test-cert.pem" --key "$TEST_TMPROOT/test-key.pem" \
  --port-file "$HTTPS_PORT_FILE" \
  --directory "$FIXTURES_DIR"
SERVER_PIDS+=("$(cat "${HTTPS_PORT_FILE}.pid")")
HTTPS_PORT="$(cat "$HTTPS_PORT_FILE")"

"$FFMPEG" -y -tls_verify 0 -i "https://127.0.0.1:${HTTPS_PORT}/video_h264_aac.mp4" -c copy "$TEST_TMPROOT/t16.mp4" 2>/dev/null
if "$FFPROBE" -show_format "$TEST_TMPROOT/t16.mp4" 2>/dev/null | grep -q "format_name=mov"; then
  pass
else
  fail "HTTPS stream not mov format"
fi

# === #17 Binary compliance ===
run_test 17 "Binary compliance"
COMPLIANCE_OK=true
for bin in "$FFMPEG" "$FFPROBE"; do
  BIN_NAME="$(basename "$bin")"

  ARCHS="$(lipo -archs "$bin" 2>/dev/null)" || { fail "lipo failed on $BIN_NAME"; COMPLIANCE_OK=false; break; }
  [[ "$ARCHS" == "arm64" ]] || { fail "$BIN_NAME not arm64-only (got: $ARCHS)"; COMPLIANCE_OK=false; break; }

  DYLIBS="$(otool -L "$bin" | grep -v /usr/lib | grep -v /System | tail -n +2)"
  [[ -z "$DYLIBS" ]] || { fail "$BIN_NAME has non-system dylibs: $DYLIBS"; COMPLIANCE_OK=false; break; }

  MINOS_VER="$(vtool -show "$bin" 2>/dev/null | grep -i minos | head -1 | grep -oE '[0-9]+\.[0-9]+')"
  MINOS_MAJOR="${MINOS_VER%%.*}"; MINOS_MINOR="${MINOS_VER#*.}"
  if [[ -z "$MINOS_VER" ]] || (( MINOS_MAJOR > 14 )) || (( MINOS_MAJOR == 14 && MINOS_MINOR > 0 )); then
    fail "$BIN_NAME minos ($MINOS_VER) exceeds 14.0"; COMPLIANCE_OK=false; break
  fi

  BUILDCONF="$("$bin" -buildconf 2>&1)"
  echo "$BUILDCONF" | grep -qE '\-\-enable-gpl|\-\-enable-nonfree' && \
    { fail "$BIN_NAME contains GPL/nonfree"; COMPLIANCE_OK=false; break; }
  "$bin" -L 2>&1 | grep -q "Lesser General Public License" || \
    { fail "$BIN_NAME -L does not confirm LGPL"; COMPLIANCE_OK=false; break; }
done
$COMPLIANCE_OK && pass

# === #18 Opus → MP3 ===
run_test 18 "Opus → MP3"
"$FFMPEG" -y -i "$FIXTURES_DIR/audio_opus.ogg" -c:a libmp3lame "$TEST_TMPROOT/t18.mp3" 2>/dev/null
if "$FFPROBE" -show_streams "$TEST_TMPROOT/t18.mp3" 2>/dev/null | grep -q "codec_name=mp3"; then
  pass
else
  fail "codec not mp3"
fi

# === #19 Vorbis → MP3 ===
run_test 19 "Vorbis → MP3"
"$FFMPEG" -y -i "$FIXTURES_DIR/audio_vorbis.ogg" -c:a libmp3lame "$TEST_TMPROOT/t19.mp3" 2>/dev/null
if "$FFPROBE" -show_streams "$TEST_TMPROOT/t19.mp3" 2>/dev/null | grep -q "codec_name=mp3"; then
  pass
else
  fail "codec not mp3"
fi

# === #20 MP3 → M4A ===
run_test 20 "MP3 → M4A"
"$FFMPEG" -y -i "$FIXTURES_DIR/audio_mp3.mp3" -c:a aac "$TEST_TMPROOT/t20.m4a" 2>/dev/null
if "$FFPROBE" -show_streams "$TEST_TMPROOT/t20.m4a" 2>/dev/null | grep -q "codec_name=aac"; then
  pass
else
  fail "codec not aac"
fi

# === #21 FLAC → MP3 ===
run_test 21 "FLAC → MP3"
"$FFMPEG" -y -i "$FIXTURES_DIR/audio_flac.flac" -c:a libmp3lame "$TEST_TMPROOT/t21.mp3" 2>/dev/null
if "$FFPROBE" -show_streams "$TEST_TMPROOT/t21.mp3" 2>/dev/null | grep -q "codec_name=mp3"; then
  pass
else
  fail "codec not mp3"
fi

# === #22 AC-3 → MP3 ===
run_test 22 "AC-3 → MP3"
"$FFMPEG" -y -i "$FIXTURES_DIR/audio_ac3.mp4" -c:a libmp3lame "$TEST_TMPROOT/t22.mp3" 2>/dev/null
if "$FFPROBE" -show_streams "$TEST_TMPROOT/t22.mp3" 2>/dev/null | grep -q "codec_name=mp3"; then
  pass
else
  fail "codec not mp3"
fi

# === #23 PCM → MP3 ===
run_test 23 "PCM → MP3"
"$FFMPEG" -y -i "$FIXTURES_DIR/audio_pcm.wav" -c:a libmp3lame "$TEST_TMPROOT/t23.mp3" 2>/dev/null
if "$FFPROBE" -show_streams "$TEST_TMPROOT/t23.mp3" 2>/dev/null | grep -q "codec_name=mp3"; then
  pass
else
  fail "codec not mp3"
fi

# === #24 DASH fMP4 merge ===
run_test 24 "DASH fMP4 merge"
cat "$FIXTURES_DIR/dash/init.mp4" "$FIXTURES_DIR/dash/seg0.m4s" > "$TEST_TMPROOT/t24_combined.mp4"
"$FFMPEG" -y -i "$TEST_TMPROOT/t24_combined.mp4" -c copy "$TEST_TMPROOT/t24.mp4" 2>/dev/null
if "$FFPROBE" -show_format "$TEST_TMPROOT/t24.mp4" 2>/dev/null | grep -q "format_name"; then
  pass
else
  fail "DASH fMP4 output not probeable"
fi

# === #25 WebP thumbnail embed ===
run_test 25 "WebP thumbnail embed"
"$FFMPEG" -y -i "$FIXTURES_DIR/video_h264_aac.mp4" -i "$FIXTURES_DIR/thumb_webp.webp" \
  -map 0 -map 1 -c copy -c:v:1 png -disposition:v:1 attached_pic \
  "$TEST_TMPROOT/t25.mp4" 2>/dev/null
if "$FFPROBE" -show_streams "$TEST_TMPROOT/t25.mp4" 2>/dev/null | grep -q "attached_pic=1"; then
  pass
else
  fail "WebP thumbnail not embedded"
fi

# === #26 PNG thumbnail embed ===
run_test 26 "PNG thumbnail embed"
"$FFMPEG" -y -i "$FIXTURES_DIR/video_h264_aac.mp4" -i "$FIXTURES_DIR/thumb_png.png" \
  -map 0 -map 1 -c copy -c:v:1 png -disposition:v:1 attached_pic \
  "$TEST_TMPROOT/t26.mp4" 2>/dev/null
if "$FFPROBE" -show_streams "$TEST_TMPROOT/t26.mp4" 2>/dev/null | grep -q "attached_pic=1"; then
  pass
else
  fail "PNG thumbnail not embedded"
fi

echo ""
echo "=== Fixture test results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] || { echo "FATAL: fixture tests failed" >&2; exit 1; }
