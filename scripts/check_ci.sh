#!/usr/bin/env bash

echo "scripts/check_ci.sh 已弃用，请改用 tools/check_ci.sh" >&2
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../tools/check_ci.sh" "$@"
