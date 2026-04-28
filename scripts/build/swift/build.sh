#!/usr/bin/env zsh
# M3 build pipeline for YTTool.app
#
# Modes:
#   --dev      (default) Use existing Resources/Binaries; skip prepare_binaries.
#              Requires dev_install_binaries.sh to have been run first.
#   --release  Download pinned binaries via prepare_binaries.py before building.
#              Requires SHAs to be set in pinned_versions.sh.
#
# Options:
#   --channel NAME      yt-dlp channel: stable (default) or nightly
#   --output DIR        Output directory (default: swift/dist)
#   --archive PATH      Path for the .xcarchive (default: tmp/swift-build/YTTool.xcarchive)
#   --derived-data DIR  Path for Xcode DerivedData (default: tmp/swift-build/DerivedData)
#   --clean        Force re-download of binaries (release mode only)
#   --skip-test    Skip smoke_test after build
#
# Usage examples:
#   scripts/build/swift/build.sh
#   scripts/build/swift/build.sh --release --output /tmp/dist
#   scripts/build/swift/build.sh --output /tmp/dist --skip-test

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
XCPROJECT="$PROJECT_DIR/swift/YTTool.xcodeproj"
SCHEME="YTTool"
BINARIES_SRC="$PROJECT_DIR/swift/YTTool/Resources/Binaries"

# ── Defaults ──────────────────────────────────────────────────────────────────
MODE="dev"
CHANNEL="stable"
OUTPUT_DIR="$PROJECT_DIR/swift/dist"
BUILD_ROOT="$PROJECT_DIR/tmp/swift-build"
ARCHIVE_PATH="$BUILD_ROOT/YTTool.xcarchive"
DERIVED_DATA_PATH="$BUILD_ROOT/DerivedData"
CLEAN_FLAG=""
SKIP_TEST=0

# ── Arg parsing ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dev)        MODE="dev";     shift ;;
        --release)    MODE="release"; shift ;;
        --channel)       CHANNEL="$2"; shift 2 ;;
        --output)        OUTPUT_DIR="$2"; shift 2 ;;
        --archive)       ARCHIVE_PATH="$2"; shift 2 ;;
        --derived-data)  DERIVED_DATA_PATH="$2"; shift 2 ;;
        --clean)         CLEAN_FLAG="--clean"; shift ;;
        --skip-test)     SKIP_TEST=1; shift ;;
        -h|--help)
            sed -n '2,25p' "$0"; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

DIST_APP="$OUTPUT_DIR/YTTool.app"
DIST_ZIP="$OUTPUT_DIR/YTTool.zip"
XCODE_LOG="$BUILD_ROOT/xcodebuild-archive.log"

# ── Helpers ───────────────────────────────────────────────────────────────────
step() { echo ""; echo "==> $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }
read_ytdlp_version() {
    local binary_path="$1"
    local version
    version="$("$binary_path" --version 2>/dev/null | head -n 1 | tr -d '\r')" || return 1
    [[ -n "$version" ]] || return 1
    echo "$version"
}

# ── Step 1: Prepare binaries ──────────────────────────────────────────────────
step "1/6  Prepare binaries (mode: $MODE, channel: $CHANNEL)"

source "$SCRIPT_DIR/pinned_versions.sh"
set_ytdlp_channel_vars "$CHANNEL"

if [[ "$MODE" == "release" ]]; then
    if [[ "$CHANNEL" == "nightly" && -z "$YTDLP_SHA256" ]]; then
        die "YTDLP_NIGHTLY_SHA256 is empty. Pin the nightly release before using --channel nightly in release mode."
    fi
    for var in YTDLP_URL YTDLP_SHA256 FFMPEG_URL FFMPEG_SHA256 FFPROBE_URL FFPROBE_SHA256; do
        val="${(P)var}"
        [[ -n "$val" ]] || die "$var is empty. Fill in pinned_versions.sh (run compute_shas.sh)."
    done
    # Release always passes --clean so that any stale dev binaries (e.g. from
    # dev_install_binaries.sh) are replaced by the pinned, SHA-verified versions.
    # This prevents a prior dev run from silently defeating supply-chain checks.
    python3 "$SCRIPT_DIR/prepare_binaries.py" \
        --vendor-bin-dir "$BINARIES_SRC" \
        --clean \
        --ytdlp-url     "$YTDLP_URL"     --ytdlp-sha256   "$YTDLP_SHA256" \
        --ffmpeg-url    "$FFMPEG_URL"    --ffmpeg-sha256  "$FFMPEG_SHA256" \
        --ffprobe-url   "$FFPROBE_URL"   --ffprobe-sha256 "$FFPROBE_SHA256"
else
    current_ytdlp="$BINARIES_SRC/yt-dlp"
    [[ -e "$current_ytdlp" ]] || die "Binary not found: $current_ytdlp\nRun: scripts/build/swift/dev_install_binaries.sh --channel $CHANNEL"
    current_ytdlp_version="$(read_ytdlp_version "$current_ytdlp" || true)"
    if [[ "$current_ytdlp_version" != "$YTDLP_VERSION" ]]; then
        die "dev mode yt-dlp channel mismatch: requested $CHANNEL ($YTDLP_VERSION) but found ${current_ytdlp_version:-unknown} in $current_ytdlp\nRun: scripts/build/swift/dev_install_binaries.sh --channel $CHANNEL"
    fi
    echo "dev mode: using existing binaries in $BINARIES_SRC (channel: $CHANNEL, yt-dlp version: $current_ytdlp_version)"
fi

# Verify binaries exist
for bin in yt-dlp ffmpeg ffprobe; do
    bin_path="$BINARIES_SRC/$bin"
    if [[ ! -e "$bin_path" ]]; then
        die "Binary not found: $bin_path\nRun: scripts/build/swift/dev_install_binaries.sh --channel $CHANNEL"
    fi
    if [[ ! -x "$bin_path" ]]; then
        chmod +x "$bin_path"
        echo "  Fixed permissions: $bin_path"
    fi
    echo "  $bin: OK"
done

# ── Step 2: Archive ───────────────────────────────────────────────────────────
step "2/6  xcodebuild archive"

mkdir -p "$BUILD_ROOT" "$OUTPUT_DIR"
rm -rf "$ARCHIVE_PATH"
rm -rf "$DERIVED_DATA_PATH"
# Write raw xcodebuild output to a log file so that the exit code is not masked
# by a downstream pipe.  Filter relevant lines to stdout for readability while
# the full log is preserved for post-mortem inspection on failure.
xcodebuild archive \
    -project "$XCPROJECT" \
    -scheme  "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    DEVELOPMENT_TEAM="" \
    > "$XCODE_LOG" 2>&1 \
    || { grep -E "^(error:|warning:|Build FAILED)" "$XCODE_LOG" | head -20 >&2
         echo "Full log: $XCODE_LOG" >&2
         die "xcodebuild archive failed (see log above)"; }
grep -E "^(warning:|note:)" "$XCODE_LOG" || true

# Check it actually produced an archive
[[ -d "$ARCHIVE_PATH" ]] || die "Archive not created: $ARCHIVE_PATH"
APP_IN_ARCHIVE="$ARCHIVE_PATH/Products/Applications/YTTool.app"
[[ -d "$APP_IN_ARCHIVE" ]] || die "App not found in archive: $APP_IN_ARCHIVE"
echo "  Archive: $ARCHIVE_PATH"
echo "  DerivedData: $DERIVED_DATA_PATH"
echo "  xcodebuild log: $XCODE_LOG"

# ── Step 3: Export .app ───────────────────────────────────────────────────────
step "3/6  Export .app"

rm -rf "$DIST_APP"
cp -R "$APP_IN_ARCHIVE" "$DIST_APP"
echo "  Exported: $DIST_APP"

# ── Step 4: Codesign ─────────────────────────────────────────────────────────
step "4/6  Ad-hoc codesign"

BINARIES_IN_APP="$DIST_APP/Contents/Resources/Binaries"
if [[ ! -d "$BINARIES_IN_APP" ]]; then
    die "Binaries dir not found in app bundle: $BINARIES_IN_APP\nCheck that the Binaries folder is in the Xcode Resources build phase."
fi

echo "  Signing vendored binaries..."
for bin_path in "$BINARIES_IN_APP"/*; do
    [[ -f "$bin_path" ]] || continue
    codesign --force --sign - "$bin_path"
    echo "    $(basename "$bin_path"): signed"
done

echo "  Signing app bundle..."
codesign --force --deep --sign - "$DIST_APP"
echo "  App bundle: signed"

# ── Step 5: Package ───────────────────────────────────────────────────────────
step "5/6  Create distribution zip"

rm -f "$DIST_ZIP"
pushd "$OUTPUT_DIR" > /dev/null
zip -qr "YTTool.zip" "YTTool.app"
popd > /dev/null
ZIP_SIZE="$(du -sh "$DIST_ZIP" | cut -f1)"
echo "  $DIST_ZIP  ($ZIP_SIZE)"

# ── Step 6: Smoke test ────────────────────────────────────────────────────────
step "6/6  Smoke test"

if [[ $SKIP_TEST -eq 1 ]]; then
    echo "  (skipped via --skip-test)"
else
    "$SCRIPT_DIR/smoke_test.sh" "$DIST_APP"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "Build complete."
echo "  App : $DIST_APP"
echo "  Zip : $DIST_ZIP ($ZIP_SIZE)"
