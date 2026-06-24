#!/usr/bin/env bash
set -euo pipefail

# Build minimal LGPL ffmpeg + ffprobe for yt-tool (arm64 macOS).
# Source lock: all upstream versions, URLs, and SHA256 hashes are pinned.
# See DOCS/handoffs/custom-ffmpeg-build/01-producer.md for spec.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Source Lock ---
FFMPEG_VERSION="8.1.1"
LAME_VERSION="3.100"
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
FFMPEG_SIG_URL="${FFMPEG_URL}.asc"
LAME_URL="https://sourceforge.net/projects/lame/files/lame/${LAME_VERSION}/lame-${LAME_VERSION}.tar.gz"
FFMPEG_SHA256="b6863adde98898f42602017462871b5f6333e65aec803fdd7a6308639c52edf3"
LAME_SHA256="ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e"
EXPECTED_PGP_FINGERPRINT="FCF986EA15E6E293A5644F10B4322F04D67658D8"

BUILD_REVISION="${BUILD_REVISION:-local}"

# --- Build directories ---
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ffmpeg-build.XXXXXX")"
OUTPUT_DIR="${OUTPUT_DIR:-$BUILD_DIR/output}"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
PREFIX="${BUILD_DIR}/prefix"
mkdir -p "$PREFIX"
BUILD_GNUPGHOME=""
cleanup_build() {
  if [[ -n "$BUILD_GNUPGHOME" ]]; then
    rm -rf -- "$BUILD_GNUPGHOME"
  fi
  echo "Build dir: $BUILD_DIR / Output dir: $OUTPUT_DIR"
}
trap cleanup_build EXIT

# --- Source download + SHA256 verify ---
echo "=== Downloading sources ==="
curl -fSL -o "$BUILD_DIR/ffmpeg.tar.xz" "$FFMPEG_URL"
curl -fSL -o "$BUILD_DIR/ffmpeg.tar.xz.asc" "$FFMPEG_SIG_URL"
curl -fSL -o "$BUILD_DIR/lame.tar.gz" "$LAME_URL"

ACTUAL_FFMPEG_SHA="$(shasum -a 256 "$BUILD_DIR/ffmpeg.tar.xz" | cut -d' ' -f1)"
[[ "$ACTUAL_FFMPEG_SHA" == "$FFMPEG_SHA256" ]] || \
  { echo "FATAL: FFmpeg SHA256 mismatch (got $ACTUAL_FFMPEG_SHA)" >&2; exit 1; }
ACTUAL_LAME_SHA="$(shasum -a 256 "$BUILD_DIR/lame.tar.gz" | cut -d' ' -f1)"
[[ "$ACTUAL_LAME_SHA" == "$LAME_SHA256" ]] || \
  { echo "FATAL: LAME SHA256 mismatch (got $ACTUAL_LAME_SHA)" >&2; exit 1; }

# --- PGP verify ---
echo "=== PGP verification ==="
command -v gpg &>/dev/null || { echo "FATAL: gpg not found" >&2; exit 1; }

BUILD_GNUPGHOME="$(mktemp -d)"
export GNUPGHOME="$BUILD_GNUPGHOME"

gpg --import "$SCRIPT_DIR/ffmpeg-release.asc"

IMPORTED_FP="$(gpg --with-colons --fingerprint 2>/dev/null \
  | grep '^fpr:' | head -1 | cut -d: -f10)"
if [[ "$IMPORTED_FP" != "$EXPECTED_PGP_FINGERPRINT" ]]; then
  echo "FATAL: imported key fingerprint mismatch" >&2; exit 1
fi

GPG_STATUS="$(gpg --status-fd 1 --verify \
  "$BUILD_DIR/ffmpeg.tar.xz.asc" "$BUILD_DIR/ffmpeg.tar.xz" 2>/dev/null)"

SIGNER_FP="$(echo "$GPG_STATUS" | grep '^\[GNUPG:\] VALIDSIG' | awk '{print $3}')"
PRIMARY_FP="$(echo "$GPG_STATUS" | grep '^\[GNUPG:\] VALIDSIG' | awk '{print $12}')"
CHECK_FP="${PRIMARY_FP:-$SIGNER_FP}"

if [[ "$CHECK_FP" != "$EXPECTED_PGP_FINGERPRINT" ]]; then
  echo "FATAL: signature not from expected key" >&2
  echo "  expected: $EXPECTED_PGP_FINGERPRINT" >&2
  echo "  actual:   $CHECK_FP (signer=$SIGNER_FP, primary=$PRIMARY_FP)" >&2
  exit 1
fi

# --- Extract ---
echo "=== Extracting sources ==="
cd "$BUILD_DIR"
tar xf ffmpeg.tar.xz
tar xzf lame.tar.gz

# --- LAME build ---
echo "=== Building LAME ==="
cd "$BUILD_DIR/lame-${LAME_VERSION}"
./configure \
  --prefix="$PREFIX" \
  --host=aarch64-apple-darwin \
  CC=/usr/bin/clang \
  CFLAGS="-arch arm64 -mmacosx-version-min=14.0" \
  LDFLAGS="-arch arm64 -mmacosx-version-min=14.0" \
  --disable-shared \
  --enable-static \
  --disable-frontend \
  --disable-decoder \
  --enable-nasm
make -j"$(sysctl -n hw.logicalcpu)"
make install

[[ -f "$PREFIX/lib/libmp3lame.a" ]] || { echo "FATAL: libmp3lame.a not found after install" >&2; exit 1; }
[[ ! -f "$PREFIX/lib/libmp3lame.dylib" ]] || { echo "FATAL: shared libmp3lame found (expected static only)" >&2; exit 1; }
[[ -f "$PREFIX/include/lame/lame.h" ]] || \
  { echo "FATAL: lame.h not found at $PREFIX/include/lame/" >&2; exit 1; }

# --- FFmpeg configure + build ---
echo "=== Building FFmpeg ==="
unset PKG_CONFIG_PATH
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
export MACOSX_DEPLOYMENT_TARGET=14.0

configure_args=(
  --arch=arm64
  --target-os=darwin
  --cc=/usr/bin/clang

  --enable-static
  --disable-shared
  --disable-doc
  --disable-debug
  --enable-small
  --disable-everything
  --disable-autodetect
  --fatal-warnings

  --extra-cflags="-I${PREFIX}/include -mmacosx-version-min=14.0"
  --extra-ldflags="-L${PREFIX}/lib -mmacosx-version-min=14.0"
  --pkg-config-flags=--static

  --enable-zlib
  --enable-securetransport

  # Programs
  --enable-ffmpeg
  --enable-ffprobe

  # Protocols (HTTP family only — see protocol decision in entry doc)
  --enable-protocol=file
  --enable-protocol=pipe
  --enable-protocol=concat
  --enable-protocol=http
  --enable-protocol=https
  --enable-protocol=tcp
  --enable-protocol=tls
  --enable-protocol=crypto
  --enable-protocol=data
  --enable-protocol=httpproxy

  # Demuxers
  --enable-demuxer=mov
  --enable-demuxer=matroska
  --enable-demuxer=mp3
  --enable-demuxer=ogg
  --enable-demuxer=flac
  --enable-demuxer=wav
  --enable-demuxer=aac
  --enable-demuxer=ass
  --enable-demuxer=srt
  --enable-demuxer=webvtt
  --enable-demuxer=concat
  --enable-demuxer=image2
  --enable-demuxer=image2pipe
  --enable-demuxer=mpegts
  --enable-demuxer=hls
  --enable-demuxer=ffmetadata

  # Muxers
  --enable-muxer=mp4
  --enable-muxer=matroska
  --enable-muxer=webm
  --enable-muxer=mp3
  --enable-muxer=ogg
  --enable-muxer=flac
  --enable-muxer=ipod
  --enable-muxer=opus
  --enable-muxer=adts
  --enable-muxer=wav
  --enable-muxer=image2
  --enable-muxer=null
  --enable-muxer=mpegts
  --enable-muxer=ffmetadata

  # Decoders
  --enable-decoder=h264
  --enable-decoder=hevc
  --enable-decoder=vp8
  --enable-decoder=vp9
  --enable-decoder=av1
  --enable-decoder=aac
  --enable-decoder=opus
  --enable-decoder=vorbis
  --enable-decoder=mp3
  --enable-decoder=mp3float
  --enable-decoder=flac
  --enable-decoder=pcm_s16le
  --enable-decoder=pcm_s24le
  --enable-decoder=pcm_s32le
  --enable-decoder=pcm_f32le
  --enable-decoder=ac3
  --enable-decoder=eac3
  --enable-decoder=alac
  --enable-decoder=mjpeg
  --enable-decoder=png
  --enable-decoder=webp
  --enable-decoder=ass
  --enable-decoder=srt
  --enable-decoder=webvtt
  --enable-decoder=movtext

  # Encoders
  --enable-encoder=aac
  --enable-encoder=libmp3lame
  --enable-encoder=pcm_s16le
  --enable-encoder=pcm_s24le
  --enable-encoder=pcm_f32le
  --enable-encoder=mjpeg
  --enable-encoder=png

  # Parsers
  --enable-parser=h264
  --enable-parser=hevc
  --enable-parser=vp8
  --enable-parser=vp9
  --enable-parser=av1
  --enable-parser=aac
  --enable-parser=opus
  --enable-parser=vorbis
  --enable-parser=mpegaudio
  --enable-parser=flac
  --enable-parser=ac3
  --enable-parser=mjpeg
  --enable-parser=png
  --enable-parser=webp

  # Bitstream filters
  --enable-bsf=h264_mp4toannexb
  --enable-bsf=hevc_mp4toannexb
  --enable-bsf=aac_adtstoasc
  --enable-bsf=extract_extradata
  --enable-bsf=vp9_superframe
  --enable-bsf=av1_metadata
  --enable-bsf=setts

  # Filters
  --enable-filter=aresample
  --enable-filter=aformat
  --enable-filter=anull
  --enable-filter=null
  --enable-filter=scale
  --enable-filter=copy
  --enable-filter=concat
  --enable-filter=atrim
  --enable-filter=trim

  # External libraries
  --enable-libmp3lame

  # Hardware
  --enable-neon
  --enable-runtime-cpudetect
)

cd "$BUILD_DIR/ffmpeg-${FFMPEG_VERSION}"
./configure "${configure_args[@]}" --prefix="$PREFIX"
make -j"$(sysctl -n hw.logicalcpu)"

# Verify libmp3lame linked
BUILDCONF_OUT="$("$BUILD_DIR/ffmpeg-${FFMPEG_VERSION}/ffmpeg" -buildconf 2>&1)"
echo "$BUILDCONF_OUT" | grep -q '\-\-enable-libmp3lame' || \
  { echo "FATAL: ffmpeg not built with libmp3lame" >&2; exit 1; }

# --- Strip ---
echo "=== Stripping binaries ==="
strip "$BUILD_DIR/ffmpeg-${FFMPEG_VERSION}/ffmpeg"
strip "$BUILD_DIR/ffmpeg-${FFMPEG_VERSION}/ffprobe"

# --- Compliance checks ---
echo "=== Compliance checks ==="
for bin in ffmpeg ffprobe; do
  BIN_PATH="$BUILD_DIR/ffmpeg-${FFMPEG_VERSION}/$bin"

  ARCHS="$(lipo -archs "$BIN_PATH" 2>/dev/null)" || { echo "FATAL: lipo failed on $bin" >&2; exit 1; }
  [[ "$ARCHS" == "arm64" ]] || { echo "FATAL: $bin not arm64-only (got: $ARCHS)" >&2; exit 1; }

  DYLIBS="$(otool -L "$BIN_PATH" | grep -v /usr/lib | grep -v /System | tail -n +2)"
  [[ -z "$DYLIBS" ]] || { echo "FATAL: $bin has non-system dylibs: $DYLIBS" >&2; exit 1; }

  MINOS_VER="$(vtool -show "$BIN_PATH" 2>/dev/null | grep -i minos | head -1 | grep -oE '[0-9]+\.[0-9]+')"
  MINOS_MAJOR="${MINOS_VER%%.*}"; MINOS_MINOR="${MINOS_VER#*.}"
  if [[ -z "$MINOS_VER" ]] || (( MINOS_MAJOR > 14 )) || (( MINOS_MAJOR == 14 && MINOS_MINOR > 0 )); then
    echo "FATAL: $bin minos ($MINOS_VER) exceeds 14.0" >&2; exit 1
  fi

  BUILDCONF="$("$BIN_PATH" -buildconf 2>&1)"
  echo "$BUILDCONF" | grep -qE '\-\-enable-gpl|\-\-enable-nonfree' && \
    { echo "FATAL: $bin contains GPL/nonfree" >&2; exit 1; }
  "$BIN_PATH" -L 2>&1 | grep -q "Lesser General Public License" || \
    { echo "FATAL: $bin -L does not confirm LGPL" >&2; exit 1; }

  echo "$bin size: $(stat -f%z "$BIN_PATH") bytes"
done

# --- Fixture tests ---
echo "=== Running fixture tests ==="
"$SCRIPT_DIR/test_minimal.sh" \
  "$BUILD_DIR/ffmpeg-${FFMPEG_VERSION}/ffmpeg" \
  "$BUILD_DIR/ffmpeg-${FFMPEG_VERSION}/ffprobe"

# --- yt-dlp integration tests ---
echo "=== Running yt-dlp integration tests ==="
"$SCRIPT_DIR/test_ytdlp_integration.sh" \
  "$BUILD_DIR/ffmpeg-${FFMPEG_VERSION}"

# --- BUILDINFO ---
echo "=== Generating artifacts ==="
FFMPEG_BIN="$BUILD_DIR/ffmpeg-${FFMPEG_VERSION}/ffmpeg"
FFPROBE_BIN="$BUILD_DIR/ffmpeg-${FFMPEG_VERSION}/ffprobe"
FFMPEG_MEMBER_SHA="$(shasum -a 256 "$FFMPEG_BIN" | cut -d' ' -f1)"
FFPROBE_MEMBER_SHA="$(shasum -a 256 "$FFPROBE_BIN" | cut -d' ' -f1)"
ARCHIVE_NAME="ffmpeg-${FFMPEG_VERSION}-minimal-${BUILD_REVISION}.zip"

cat > "$OUTPUT_DIR/BUILDINFO" <<BEOF
[source]
ffmpeg_version=${FFMPEG_VERSION}
ffmpeg_url=${FFMPEG_URL}
ffmpeg_source_sha256=${FFMPEG_SHA256}
ffmpeg_signer_fingerprint=${EXPECTED_PGP_FINGERPRINT}
lame_version=${LAME_VERSION}
lame_url=${LAME_URL}
lame_source_sha256=${LAME_SHA256}

[build]
arch=arm64
macos_deployment_target=${MACOSX_DEPLOYMENT_TARGET}
xcode_version=$(xcodebuild -version | head -1)
clang_version=$(/usr/bin/clang --version | head -1)
macos_sdk=$(xcrun --show-sdk-version)
runner_image=${ImageVersion:-local}
build_revision=${BUILD_REVISION}
build_script_commit=$(git -C "$SCRIPT_DIR" rev-parse HEAD)
license=LGPL-2.1+

[checksums]
ffmpeg_member_sha256=${FFMPEG_MEMBER_SHA}
ffprobe_member_sha256=${FFPROBE_MEMBER_SHA}
BEOF

printf '%s\n' "${configure_args[@]}" > "$OUTPUT_DIR/configure.txt"

# --- License verification ---
[[ -d "$SCRIPT_DIR/licenses" ]] || { echo "FATAL: $SCRIPT_DIR/licenses/ not found" >&2; exit 1; }

cmp -s "$SCRIPT_DIR/licenses/LICENSE_LGPL.txt" "$BUILD_DIR/ffmpeg-${FFMPEG_VERSION}/COPYING.LGPLv2.1" || \
  { echo "FATAL: LICENSE_LGPL.txt differs from FFmpeg COPYING.LGPLv2.1" >&2; exit 1; }
tail -n +5 "$SCRIPT_DIR/licenses/LICENSE_LAME.txt" | cmp -s - "$BUILD_DIR/lame-${LAME_VERSION}/COPYING" || \
  { echo "FATAL: LICENSE_LAME.txt body differs from LAME COPYING" >&2; exit 1; }

# --- Generate NOTICE and Release Notes ---
sed -e "s/\${FFMPEG_VERSION}/${FFMPEG_VERSION}/g" \
    -e "s/\${LAME_VERSION}/${LAME_VERSION}/g" \
    "$SCRIPT_DIR/NOTICE_FFMPEG.template.txt" > "$OUTPUT_DIR/NOTICE_FFMPEG.txt"

sed -e "s/\${FFMPEG_VERSION}/${FFMPEG_VERSION}/g" \
    -e "s/\${LAME_VERSION}/${LAME_VERSION}/g" \
    "$SCRIPT_DIR/release_notes.template.md" > "$OUTPUT_DIR/RELEASE_NOTES.md"

# --- ZIP packaging ---
echo "=== Packaging ZIP ==="
cd "$BUILD_DIR/ffmpeg-${FFMPEG_VERSION}"
zip -j "$OUTPUT_DIR/${ARCHIVE_NAME}" \
  ffmpeg ffprobe \
  "$OUTPUT_DIR/BUILDINFO" \
  "$OUTPUT_DIR/configure.txt" \
  "$OUTPUT_DIR/NOTICE_FFMPEG.txt" \
  "$SCRIPT_DIR/licenses/"*

# ZIP exact member set verification
EXPECTED_MEMBERS="BUILDINFO
LICENSE_LAME.txt
LICENSE_LGPL.txt
NOTICE_FFMPEG.txt
configure.txt
ffmpeg
ffprobe"
ACTUAL_MEMBERS="$(zipinfo -1 "$OUTPUT_DIR/${ARCHIVE_NAME}" | sort)"
[[ "$ACTUAL_MEMBERS" == "$EXPECTED_MEMBERS" ]] || \
  { echo "FATAL: ZIP member mismatch"; echo "expected:"; echo "$EXPECTED_MEMBERS"; echo "actual:"; echo "$ACTUAL_MEMBERS"; exit 1; } >&2

# --- Source assets ---
cp "$BUILD_DIR/ffmpeg.tar.xz" "$OUTPUT_DIR/ffmpeg-${FFMPEG_VERSION}.tar.xz"
cp "$BUILD_DIR/lame.tar.gz" "$OUTPUT_DIR/lame-${LAME_VERSION}.tar.gz"

# --- SHA256SUMS (outside ZIP) ---
ARCHIVE_SHA="$(shasum -a 256 "$OUTPUT_DIR/${ARCHIVE_NAME}" | cut -d' ' -f1)"
FFMPEG_SRC_SHA="$(shasum -a 256 "$OUTPUT_DIR/ffmpeg-${FFMPEG_VERSION}.tar.xz" | cut -d' ' -f1)"
LAME_SRC_SHA="$(shasum -a 256 "$OUTPUT_DIR/lame-${LAME_VERSION}.tar.gz" | cut -d' ' -f1)"

cat > "$OUTPUT_DIR/SHA256SUMS" <<SEOF
archive_sha256=${ARCHIVE_SHA}
ffmpeg_member_sha256=${FFMPEG_MEMBER_SHA}
ffprobe_member_sha256=${FFPROBE_MEMBER_SHA}
ffmpeg_source_sha256=${FFMPEG_SRC_SHA}
lame_source_sha256=${LAME_SRC_SHA}
SEOF

# --- Audit snapshot ---
mkdir -p "$OUTPUT_DIR/audit"
"$FFMPEG_BIN" -buildconf > "$OUTPUT_DIR/audit/buildconf.txt" 2>&1
"$FFMPEG_BIN" -formats > "$OUTPUT_DIR/audit/formats.txt" 2>&1
"$FFMPEG_BIN" -codecs > "$OUTPUT_DIR/audit/codecs.txt" 2>&1
"$FFMPEG_BIN" -protocols > "$OUTPUT_DIR/audit/protocols.txt" 2>&1
"$FFMPEG_BIN" -bsfs > "$OUTPUT_DIR/audit/bsfs.txt" 2>&1
"$FFMPEG_BIN" -filters > "$OUTPUT_DIR/audit/filters.txt" 2>&1

echo "=== Build complete ==="
echo "Archive: $OUTPUT_DIR/${ARCHIVE_NAME}"
echo "SHA256SUMS: $OUTPUT_DIR/SHA256SUMS"
