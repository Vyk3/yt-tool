#!/usr/bin/env bash
set -euo pipefail
# Usage: download_pinned_ytdlp.sh <stable|nightly> <output-dir>
# Output: $OUTDIR/yt-dlp (wrapper script) and $OUTDIR/yt-dlp.zipapp (raw zipapp)
CHANNEL="$1"; OUTDIR="$2"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../build/swift/pinned_versions.sh"

case "$CHANNEL" in
  stable)  URL="$YTDLP_STABLE_URL";  SHA="$YTDLP_STABLE_SHA256" ;;
  nightly) URL="$YTDLP_NIGHTLY_URL"; SHA="$YTDLP_NIGHTLY_SHA256" ;;
  *) echo "FATAL: unknown channel $CHANNEL" >&2; exit 1 ;;
esac

mkdir -p "$OUTDIR"
curl -fsSL "$URL" -o "$OUTDIR/yt-dlp.zipapp"
ACTUAL="$(shasum -a 256 "$OUTDIR/yt-dlp.zipapp" | cut -d' ' -f1)"
if [[ "$ACTUAL" != "$SHA" ]]; then
  echo "FATAL: yt-dlp SHA mismatch (expected $SHA, got $ACTUAL)" >&2; exit 1
fi

PYTHON="$(command -v python3)" || { echo "FATAL: python3 not found" >&2; exit 1; }
PY_VER="$("$PYTHON" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
PY_MAJOR="${PY_VER%%.*}"; PY_MINOR="${PY_VER#*.}"
if (( PY_MAJOR < 3 )) || (( PY_MAJOR == 3 && PY_MINOR < 10 )); then
  echo "FATAL: python3 version $PY_VER < 3.10" >&2; exit 1
fi

cat > "$OUTDIR/yt-dlp" <<WEOF
#!/usr/bin/env bash
exec "$PYTHON" "$OUTDIR/yt-dlp.zipapp" "\$@"
WEOF
chmod +x "$OUTDIR/yt-dlp"
echo "$OUTDIR/yt-dlp"
