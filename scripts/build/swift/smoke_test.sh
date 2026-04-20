#!/usr/bin/env zsh
# Smoke-test a built YTTool.app bundle.
#
# Usage: scripts/build/swift/smoke_test.sh /path/to/YTTool.app
#
# Checks:
#   1. Bundle exists and is a directory
#   2. Executable is present
#   3. Info.plist is present
#   4. All three required binaries are present and executable
#   5. Ad-hoc codesignature is valid (codesign --verify)

set -euo pipefail

APP="${1:-}"
PASS=0
FAIL=0

_ok()   { echo "  [OK]  $*"; (( PASS+=1 )); }
_fail() { echo "  [FAIL] $*"; (( FAIL+=1 )); }

check_file_exec() {
    local path="$1"
    local label="$2"
    if [[ -f "$path" && -x "$path" ]]; then
        _ok "$label"
    elif [[ -f "$path" ]]; then
        _fail "$label — exists but not executable"
    else
        _fail "$label — missing"
    fi
}

echo "=== smoke_test: $APP ==="
echo ""

# 1. Bundle exists
if [[ -d "$APP" ]]; then
    _ok "Bundle directory exists"
else
    _fail "Bundle directory missing: $APP"
    exit 1
fi

CONTENTS="$APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
BINARIES="$RESOURCES/Binaries"
EXECUTABLE="$MACOS_DIR/YTTool"
INFO_PLIST="$CONTENTS/Info.plist"

# 2. Executable
check_file_exec "$EXECUTABLE" "Main executable: Contents/MacOS/YTTool"

# 3. Info.plist
if [[ -f "$INFO_PLIST" ]]; then
    _ok "Info.plist present"
else
    _fail "Info.plist missing"
fi

# 4. Vendored binaries
for bin in yt-dlp ffmpeg ffprobe; do
    check_file_exec "$BINARIES/$bin" "Vendored binary: Binaries/$bin"
done

# 5. Codesign (ad-hoc)
echo ""
echo "--- codesign --verify ---"
if codesign --verify --deep --strict "$APP" 2>&1; then
    _ok "codesign --verify passed"
else
    _fail "codesign --verify failed (see output above)"
fi

# Summary
echo ""
if [[ $FAIL -eq 0 ]]; then
    echo "smoke_test PASSED ($PASS checks)"
    exit 0
else
    echo "smoke_test FAILED ($FAIL/$((PASS+FAIL)) checks failed)"
    exit 1
fi
