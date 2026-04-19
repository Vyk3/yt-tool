#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -x "${REPO_ROOT}/.venv/bin/ruff" ]]; then
  RUFF=("${REPO_ROOT}/.venv/bin/ruff")
elif command -v ruff >/dev/null 2>&1; then
  RUFF=("ruff")
else
  echo "未找到 ruff。" >&2
  exit 1
fi

TARGETS=("$@")
if [[ "${#TARGETS[@]}" -eq 0 ]]; then
  TARGETS=("app" "tests")
fi

"${RUFF[@]}" check --fix "${TARGETS[@]}"
"${RUFF[@]}" format "${TARGETS[@]}"
