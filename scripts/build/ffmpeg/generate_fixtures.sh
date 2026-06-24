#!/usr/bin/env bash
set -euo pipefail

# Regenerate all test fixtures from a reference ffmpeg.
# NOT run in CI — CI only runs test_minimal.sh against the minimal binary.
# See fixtures/GENERATION.md for provenance.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
mkdir -p "$FIXTURES_DIR/hls" "$FIXTURES_DIR/dash"
cd "$FIXTURES_DIR"

FFMPEG="${FFMPEG:-ffmpeg}"
echo "Using ffmpeg: $("$FFMPEG" -version | head -1)"

"$FFMPEG" -y -f lavfi -i "testsrc2=size=320x240:rate=25:duration=3" \
  -f lavfi -i "sine=frequency=440:duration=3" \
  -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
  -c:a aac -b:a 64k \
  video_h264_aac.mp4 2>/dev/null

"$FFMPEG" -y -f lavfi -i "testsrc2=size=320x240:rate=25:duration=1" \
  -f lavfi -i "sine=frequency=440:duration=1" \
  -c:v libvpx-vp9 -b:v 200k -c:a libopus -b:a 64k \
  video_vp9_opus.webm 2>/dev/null

"$FFMPEG" -y -f lavfi -i "sine=frequency=440:duration=1" \
  -c:a aac -b:a 64k audio_aac.m4a 2>/dev/null

"$FFMPEG" -y -f lavfi -i "sine=frequency=440:duration=1" \
  -c:a eac3 -b:a 64k audio_eac3.mp4 2>/dev/null

"$FFMPEG" -y -f lavfi -i "sine=frequency=440:duration=1" \
  -c:a libopus -b:a 64k audio_opus.ogg 2>/dev/null

# Vorbis: use oggenc if libvorbis encoder unavailable in ffmpeg
if "$FFMPEG" -encoders 2>/dev/null | grep -q 'libvorbis'; then
  "$FFMPEG" -y -f lavfi -i "sine=frequency=440:duration=1" \
    -c:a libvorbis -b:a 64k audio_vorbis.ogg 2>/dev/null
else
  "$FFMPEG" -y -f lavfi -i "sine=frequency=440:duration=1" \
    -c:a pcm_s16le /tmp/vorbis_src.wav 2>/dev/null
  oggenc -q 3 -o audio_vorbis.ogg /tmp/vorbis_src.wav 2>/dev/null
  rm -f /tmp/vorbis_src.wav
fi

"$FFMPEG" -y -f lavfi -i "sine=frequency=440:duration=1" \
  -c:a libmp3lame -b:a 64k audio_mp3.mp3 2>/dev/null

"$FFMPEG" -y -f lavfi -i "sine=frequency=440:duration=1" \
  -c:a flac audio_flac.flac 2>/dev/null

"$FFMPEG" -y -f lavfi -i "sine=frequency=440:duration=1" \
  -c:a ac3 -b:a 64k audio_ac3.mp4 2>/dev/null

"$FFMPEG" -y -f lavfi -i "sine=frequency=440:duration=1" \
  -c:a pcm_s16le audio_pcm.wav 2>/dev/null

"$FFMPEG" -y -f lavfi -i "color=c=blue:s=64x64:d=1" -frames:v 1 \
  thumb_jpeg.jpg 2>/dev/null

"$FFMPEG" -y -f lavfi -i "color=c=green:s=64x64:d=1" -frames:v 1 \
  thumb_png.png 2>/dev/null

# WebP: try libwebp encoder, fall back to cwebp
if "$FFMPEG" -encoders 2>/dev/null | grep -q 'libwebp'; then
  "$FFMPEG" -y -f lavfi -i "color=c=red:s=64x64:d=1" -frames:v 1 \
    -c:v libwebp thumb_webp.webp 2>/dev/null
else
  "$FFMPEG" -y -f lavfi -i "color=c=red:s=64x64:d=1" -frames:v 1 \
    /tmp/thumb_tmp.png 2>/dev/null
  cwebp -quiet -q 50 /tmp/thumb_tmp.png -o thumb_webp.webp
  rm -f /tmp/thumb_tmp.png
fi

cat > chapters.ffmetadata << 'METAEOF'
;FFMETADATA1
[CHAPTER]
TIMEBASE=1/1000
START=0
END=1500
title=Chapter 1
[CHAPTER]
TIMEBASE=1/1000
START=1500
END=3000
title=Chapter 2
METAEOF

"$FFMPEG" -y -f lavfi -i "testsrc2=size=320x240:rate=25:duration=1" \
  -f lavfi -i "sine=frequency=440:duration=1" \
  -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
  -c:a aac -b:a 64k \
  -f mpegts segment.ts 2>/dev/null

# HLS fixtures
"$FFMPEG" -y -f lavfi -i "testsrc2=size=320x240:rate=25:duration=1" \
  -f lavfi -i "sine=frequency=440:duration=1" \
  -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
  -c:a aac -b:a 64k \
  -f mpegts hls/seg0.ts 2>/dev/null

openssl rand 16 > hls/key.bin

cat > hls/playlist.m3u8 << 'M3U8EOF'
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:0
#EXT-X-KEY:METHOD=AES-128,URI="key.bin"
#EXTINF:1.0,
seg0.ts
#EXT-X-ENDLIST
M3U8EOF

# Encrypt the HLS segment with the key (IV = sequence 0)
KEY_HEX=$(xxd -p -c 32 hls/key.bin)
openssl enc -aes-128-cbc -K "$KEY_HEX" -iv "00000000000000000000000000000000" \
  -in hls/seg0.ts -out hls/seg0_enc.ts
mv hls/seg0_enc.ts hls/seg0.ts

# DASH fixtures (fMP4 init + segment)
"$FFMPEG" -y -f lavfi -i "testsrc2=size=320x240:rate=25:duration=1" \
  -f lavfi -i "sine=frequency=440:duration=1" \
  -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
  -c:a aac -b:a 64k \
  -f dash -single_file 0 -seg_duration 10 \
  -init_seg_name 'init.mp4' -media_seg_name 'seg0.m4s' \
  dash/manifest.mpd 2>/dev/null

# Regenerate SHA256SUMS
find . -type f ! -name 'GENERATION.md' ! -name 'SHA256SUMS' ! -name '.*' \
  | sed 's|^\./||' | LC_ALL=C sort | while read -r f; do
  shasum -a 256 "$f"
done > SHA256SUMS

echo "=== Fixtures generated ==="
echo "Update GENERATION.md with current ffmpeg -buildconf output."
