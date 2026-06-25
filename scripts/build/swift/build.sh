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
DIST_DMG="$OUTPUT_DIR/YTTool.dmg"
XCODE_LOG="$BUILD_ROOT/xcodebuild-archive.log"

# ── Version from git tag ─────────────────────────────────────────────────────
# If HEAD is tagged with a semver tag (v1.2.3), inject it as MARKETING_VERSION.
# Falls back to the version in the Xcode project if no tag is present.
GIT_TAG="$(git -C "$PROJECT_DIR" describe --tags --exact-match HEAD 2>/dev/null || true)"
if [[ "$GIT_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    APP_VERSION="${GIT_TAG#v}"
    VERSION_OVERRIDE="MARKETING_VERSION=$APP_VERSION"
    echo "Version from git tag: $APP_VERSION"
else
    VERSION_OVERRIDE=""
    echo "No semver tag on HEAD — using Xcode project version"
fi

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
step "1/8  Prepare binaries (mode: $MODE, channel: $CHANNEL)"

source "$SCRIPT_DIR/pinned_versions.sh"
set_ytdlp_channel_vars "$CHANNEL"

if [[ "$MODE" == "release" ]]; then
    if [[ "$CHANNEL" == "nightly" && -z "$YTDLP_SHA256" ]]; then
        die "YTDLP_NIGHTLY_SHA256 is empty. Pin the nightly release before using --channel nightly in release mode."
    fi
    for var in YTDLP_URL YTDLP_SHA256 FFMPEG_URL FFMPEG_ARCHIVE_SHA256 FFMPEG_BIN_SHA256 FFPROBE_BIN_SHA256; do
        val="${(P)var}"
        [[ -n "$val" ]] || die "$var is empty. Fill in pinned_versions.sh (run compute_shas.sh)."
    done
    [[ "$(uname -m)" == "arm64" ]] || die "Release builds are arm64-only and must run on Apple Silicon."
    LICENSES_DIR="$PROJECT_DIR/swift/YTTool/Resources/Licenses"
    python3 "$SCRIPT_DIR/prepare_binaries.py" \
        --vendor-bin-dir "$BINARIES_SRC" \
        --clean \
        --ytdlp-url              "$YTDLP_URL"              --ytdlp-sha256   "$YTDLP_SHA256" \
        --ffmpeg-url             "$FFMPEG_URL" \
        --ffmpeg-archive-sha256  "$FFMPEG_ARCHIVE_SHA256" \
        --ffmpeg-sha256          "$FFMPEG_BIN_SHA256" \
        --ffprobe-sha256         "$FFPROBE_BIN_SHA256" \
        --licenses-dir           "$LICENSES_DIR"
else
    current_ytdlp="$BINARIES_SRC/yt-dlp"
    [[ -e "$current_ytdlp" ]] || die "yt-dlp not found: $current_ytdlp\nRun: scripts/build/swift/dev_install_binaries.sh --channel $CHANNEL"
    current_ytdlp_version="$(read_ytdlp_version "$current_ytdlp" || true)"
    if [[ "$current_ytdlp_version" != "$YTDLP_VERSION" ]]; then
        die "dev mode yt-dlp channel mismatch: requested $CHANNEL ($YTDLP_VERSION) but found ${current_ytdlp_version:-unknown} in $current_ytdlp\nRun: scripts/build/swift/dev_install_binaries.sh --channel $CHANNEL"
    fi
    echo "dev mode: using existing binaries in $BINARIES_SRC (channel: $CHANNEL, yt-dlp version: $current_ytdlp_version)"
fi

# Verify binaries exist (yt-dlp wrapper + zipapp + ffmpeg + ffprobe)
for bin in yt-dlp yt-dlp-zipapp ffmpeg ffprobe; do
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
step "2/8  xcodebuild archive"

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
    ARCHS=arm64 \
    ${VERSION_OVERRIDE:+"$VERSION_OVERRIDE"} \
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
step "3/8  Export .app"

rm -rf "$DIST_APP"
cp -R "$APP_IN_ARCHIVE" "$DIST_APP"
echo "  Exported: $DIST_APP"

# ── Step 4: Embed Python runtime (release only) ─────────────────────────────
step "4/8  Embed Python runtime"

PYTHON_IN_APP="$DIST_APP/Contents/Resources/Python"
if [[ "$MODE" == "release" ]]; then
    PYTHON_STAGING="$BUILD_ROOT/python-runtime"
    "$SCRIPT_DIR/prepare_python.sh" --output "$PYTHON_STAGING"
    cp -R "$PYTHON_STAGING" "$PYTHON_IN_APP"
    echo "  Embedded: $PYTHON_IN_APP ($(du -sh "$PYTHON_IN_APP" | cut -f1))"
else
    echo "  (skipped in dev mode — wrapper falls back to system python3)"
fi

# ── Step 5: Codesign ─────────────────────────────────────────────────────────
step "5/8  Ad-hoc codesign"

ENTITLEMENTS="$XCPROJECT/../YTTool/YTTool.entitlements"
if [[ ! -f "$ENTITLEMENTS" ]]; then
    die "Entitlements file not found: $ENTITLEMENTS"
fi

BINARIES_IN_APP="$DIST_APP/Contents/Resources/Binaries"
if [[ ! -d "$BINARIES_IN_APP" ]]; then
    die "Binaries dir not found in app bundle: $BINARIES_IN_APP\nCheck that the Binaries folder is in the Xcode Resources build phase."
fi

echo "  Signing vendored binaries..."
for bin_path in "$BINARIES_IN_APP"/*; do
    [[ -f "$bin_path" ]] || continue
    codesign --force --sign - --entitlements "$ENTITLEMENTS" "$bin_path"
    echo "    $(basename "$bin_path"): signed"
done

if [[ -d "$PYTHON_IN_APP" ]]; then
    echo "  Signing embedded Python runtime (all Mach-O files)..."
    PYTHON_SIGNED=0
    while IFS= read -r macho_file; do
        codesign --force --sign - --entitlements "$ENTITLEMENTS" "$macho_file"
        echo "    $(echo "$macho_file" | sed "s|$PYTHON_IN_APP/||"): signed"
        (( PYTHON_SIGNED+=1 ))
    done < <(find "$PYTHON_IN_APP" -type f -exec file {} + | grep -i 'mach-o' | cut -d: -f1)
    echo "  Python runtime: $PYTHON_SIGNED Mach-O files signed"
fi

echo "  Signing app bundle..."
codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$DIST_APP"
echo "  App bundle: signed"

# ── Step 6: Package ───────────────────────────────────────────────────────────
step "6/8  Create distribution zip"

rm -f "$DIST_ZIP"
pushd "$OUTPUT_DIR" > /dev/null
zip -qr "YTTool.zip" "YTTool.app"
popd > /dev/null
ZIP_SIZE="$(du -sh "$DIST_ZIP" | cut -f1)"
echo "  $DIST_ZIP  ($ZIP_SIZE)"

# ── Step 7: Create DMG ────────────────────────────────────────────────────────
step "7/8  Create distribution DMG"

DMG_STAGING="$BUILD_ROOT/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$DIST_APP" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

rm -f "$DIST_DMG"
hdiutil create \
    -volname "YTTool" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    -quiet \
    "$DIST_DMG"
rm -rf "$DMG_STAGING"
DMG_SIZE="$(du -sh "$DIST_DMG" | cut -f1)"
echo "  $DIST_DMG  ($DMG_SIZE)"

# ── Step 8: Smoke test ────────────────────────────────────────────────────────
step "8/8  Smoke test"

if [[ $SKIP_TEST -eq 1 ]]; then
    echo "  (skipped via --skip-test)"
else
    SMOKE_ARGS=("$DIST_APP")
    [[ "$MODE" == "release" ]] && SMOKE_ARGS=("--release" "$DIST_APP")
    "$SCRIPT_DIR/smoke_test.sh" "${SMOKE_ARGS[@]}"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "Build complete."
echo "  App : $DIST_APP"
echo "  Zip : $DIST_ZIP ($ZIP_SIZE)"
echo "  DMG : $DIST_DMG ($DMG_SIZE)"
