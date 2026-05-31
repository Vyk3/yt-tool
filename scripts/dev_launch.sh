#!/usr/bin/env zsh
# Quick dev build → launch cycle for YTTool.
#
# 1. xcodebuild Debug (arm64, no codesign)
# 2. Kill any running YTTool instance
# 3. Launch the freshly built .app bundle
#
# Usage:
#   scripts/dev_launch.sh              # build + launch
#   scripts/dev_launch.sh --skip-build # launch only (reuse last build)
#
# The DerivedData lives in tmp/dev-build/DerivedData so it doesn't pollute
# the user's global ~/Library/Developer/Xcode/DerivedData.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
XCPROJECT="$PROJECT_DIR/swift/YTTool.xcodeproj"
SCHEME="YTTool"
DERIVED_DATA="$PROJECT_DIR/tmp/dev-build/DerivedData"
SKIP_BUILD=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build) SKIP_BUILD=1; shift ;;
        -h|--help)    sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

APP_PATH="$DERIVED_DATA/Build/Products/Debug/YTTool.app"

# ── Build ─────────────────────────────────────────────────────────────────────
if [[ $SKIP_BUILD -eq 0 ]]; then
    echo "==> Building (Debug, arm64)..."
    mkdir -p "$(dirname "$DERIVED_DATA")"
    xcodebuild build \
        -project "$XCPROJECT" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -derivedDataPath "$DERIVED_DATA" \
        -arch arm64 \
        ONLY_ACTIVE_ARCH=YES \
        2>&1 | grep -E "^(Build |error:|warning:|\*\*)" || true

    if [[ ! -d "$APP_PATH" ]]; then
        echo "ERROR: Build did not produce $APP_PATH" >&2
        exit 1
    fi
    echo "==> Build OK: $APP_PATH"
fi

# ── Kill old instance ─────────────────────────────────────────────────────────
if pgrep -x YTTool > /dev/null 2>&1; then
    echo "==> Stopping running YTTool..."
    pkill -x YTTool
    # Wait up to 3 seconds for graceful exit
    for i in {1..6}; do
        pgrep -x YTTool > /dev/null 2>&1 || break
        sleep 0.5
    done
    if pgrep -x YTTool > /dev/null 2>&1; then
        echo "  Force-killing..."
        pkill -9 -x YTTool 2>/dev/null || true
    fi
fi

# ── Launch ────────────────────────────────────────────────────────────────────
if [[ ! -d "$APP_PATH" ]]; then
    echo "ERROR: App not found at $APP_PATH — run without --skip-build first" >&2
    exit 1
fi

echo "==> Launching YTTool.app..."
open "$APP_PATH"
echo "Done."
