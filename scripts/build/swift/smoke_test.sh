#!/usr/bin/env zsh
# Smoke-test a built YTTool.app bundle.
#
# Usage: scripts/build/swift/smoke_test.sh [--release] /path/to/YTTool.app
#
# Checks:
#   1. Bundle exists and is a directory
#   2. Executable is present
#   3. Info.plist is present
#   4. yt-dlp wrapper and zipapp are present and executable
#   5. ffmpeg and ffprobe are present and executable
#   6. Embedded Python runtime (if present) is functional
#   7. yt-dlp --version works via wrapper
#   8. Ad-hoc codesignature is valid (codesign --verify)

set -euo pipefail

RELEASE_MODE=0
if [[ "${1:-}" == "--release" ]]; then
    RELEASE_MODE=1
    shift
fi
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

# 4. yt-dlp wrapper and zipapp
check_file_exec "$BINARIES/yt-dlp" "Vendored binary: Binaries/yt-dlp (wrapper)"
check_file_exec "$BINARIES/yt-dlp-zipapp" "Vendored binary: Binaries/yt-dlp-zipapp"

# 5. ffmpeg and ffprobe
for bin in ffmpeg ffprobe; do
    check_file_exec "$BINARIES/$bin" "Vendored binary: Binaries/$bin"
done

# 6. Embedded Python runtime (optional for dev builds)
PYTHON_DIR="$RESOURCES/Python"
PYTHON_BIN="$PYTHON_DIR/bin/python3.12"
if [[ -d "$PYTHON_DIR" ]]; then
    if [[ -x "$PYTHON_BIN" ]]; then
        PYVER="$("$PYTHON_BIN" -c 'import sys; print(sys.version.split()[0])' 2>/dev/null || echo 'ERROR')"
        if [[ "$PYVER" != "ERROR" ]]; then
            _ok "Embedded Python runtime: $PYVER"
        else
            _fail "Embedded Python runtime — python3.12 present but broken"
        fi
    else
        _fail "Embedded Python runtime — python3.12 missing or not executable"
    fi
else
    if [[ $RELEASE_MODE -eq 1 ]]; then
        _fail "Embedded Python runtime — required for release but missing"
    else
        echo "  [SKIP] Embedded Python runtime not present (dev build)"
    fi
fi

# 7. yt-dlp --version via wrapper
YTDLP_VER="$("$BINARIES/yt-dlp" --version 2>/dev/null || echo 'ERROR')"
if [[ "$YTDLP_VER" != "ERROR" && -n "$YTDLP_VER" ]]; then
    _ok "yt-dlp --version via wrapper: $YTDLP_VER"
else
    _fail "yt-dlp --version via wrapper failed"
fi

# 8. Codesign (ad-hoc)
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
