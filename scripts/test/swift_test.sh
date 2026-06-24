#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TMP_ROOT="$PROJECT_DIR/tmp"
TEST_HOME="$TMP_ROOT/test-home"
CLANG_CACHE="$TMP_ROOT/clang-module-cache"
SWIFTPM_CACHE="$TMP_ROOT/swiftpm-module-cache"

mkdir -p "$TEST_HOME" "$CLANG_CACHE" "$SWIFTPM_CACHE"

EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --filter) EXTRA_ARGS+=(--filter "$2"); shift 2 ;;
    *)        EXTRA_ARGS+=("$1"); shift ;;
  esac
done

env \
  HOME="$TEST_HOME" \
  CLANG_MODULE_CACHE_PATH="$CLANG_CACHE" \
  SWIFTPM_MODULECACHE_OVERRIDE="$SWIFTPM_CACHE" \
  swift test --disable-sandbox --package-path "$PROJECT_DIR/swift" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}
