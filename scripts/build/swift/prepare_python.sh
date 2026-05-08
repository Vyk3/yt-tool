#!/usr/bin/env zsh
# Download and prepare a stripped, relocatable Python runtime for embedding.
#
# Usage:
#   scripts/build/swift/prepare_python.sh --output /path/to/python-runtime
#
# Sources pinned versions from pinned_versions.sh.
# The output directory will contain bin/, lib/ ready to copy into the app bundle.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/pinned_versions.sh"

OUTPUT_DIR=""
CLEAN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output) OUTPUT_DIR="$2"; shift 2 ;;
        --clean)  CLEAN=1; shift ;;
        -h|--help)
            echo "Usage: $0 --output DIR [--clean]"
            echo "Downloads and strips Python ${PYTHON_VERSION} for embedding in the app bundle."
            exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

[[ -n "$OUTPUT_DIR" ]] || { echo "ERROR: --output is required" >&2; exit 2; }

if [[ "$CLEAN" -eq 0 && -x "$OUTPUT_DIR/bin/python3.12" ]]; then
    echo "Python runtime already present: $OUTPUT_DIR"
    exit 0
fi

echo "=== Preparing embedded Python ${PYTHON_VERSION}+${PYTHON_BUILD_TAG} ==="

ARCH="$(uname -m)"
case "$ARCH" in
    arm64)
        PYTHON_URL="$PYTHON_AARCH64_URL"
        PYTHON_SHA256="$PYTHON_AARCH64_SHA256"
        ;;
    *)
        echo "ERROR: No pinned Python runtime for architecture: $ARCH" >&2
        echo "Only aarch64 (Apple Silicon) is currently supported." >&2
        exit 2
        ;;
esac

TMPDIR_PY="$(mktemp -d -t yt-tool-python)"
trap 'rm -rf "$TMPDIR_PY"' EXIT

ARCHIVE="$TMPDIR_PY/python.tar.gz"

echo "  Downloading from python-build-standalone..."
if ! curl -fsSL -o "$ARCHIVE" "$PYTHON_URL"; then
    echo "ERROR: Failed to download Python runtime" >&2
    exit 1
fi

echo "  Verifying SHA256..."
ACTUAL_SHA="$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)"
if [[ "$ACTUAL_SHA" != "$PYTHON_SHA256" ]]; then
    echo "ERROR: SHA256 mismatch" >&2
    echo "  expected: $PYTHON_SHA256" >&2
    echo "  actual:   $ACTUAL_SHA" >&2
    exit 1
fi

echo "  Extracting..."
tar xzf "$ARCHIVE" -C "$TMPDIR_PY"
EXTRACTED="$TMPDIR_PY/python"

echo "  Stripping unnecessary modules..."
STDLIB="$EXTRACTED/lib/python3.12"
rm -rf \
    "$STDLIB/test" \
    "$STDLIB/site-packages" \
    "$STDLIB/ensurepip" \
    "$STDLIB/idlelib" \
    "$STDLIB/tkinter" \
    "$STDLIB/turtledemo" \
    "$STDLIB/turtle.py" \
    "$STDLIB/lib2to3" \
    "$STDLIB/pydoc_data" \
    "$STDLIB/unittest" \
    "$STDLIB/config-3.12-darwin" \
    "$EXTRACTED/include" \
    "$EXTRACTED/share"

rm -f "$EXTRACTED"/lib/libtcl* "$EXTRACTED"/lib/libtk*
rm -rf "$EXTRACTED"/lib/tcl* "$EXTRACTED"/lib/tk*

rm -f "$EXTRACTED"/bin/2to3* "$EXTRACTED"/bin/idle* "$EXTRACTED"/bin/pip* "$EXTRACTED"/bin/pydoc*

find "$EXTRACTED" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

STRIPPED_SIZE="$(du -sh "$EXTRACTED" | cut -f1)"
echo "  Stripped size: $STRIPPED_SIZE"

echo "  Verifying runtime works..."
if ! "$EXTRACTED/bin/python3.12" -c "import sys; print(f'Python {sys.version}')" 2>/dev/null; then
    echo "ERROR: Stripped Python runtime is broken" >&2
    exit 1
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$(dirname "$OUTPUT_DIR")"
mv "$EXTRACTED" "$OUTPUT_DIR"

echo "  Python runtime ready: $OUTPUT_DIR"
