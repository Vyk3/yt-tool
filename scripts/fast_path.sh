#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

usage() {
  cat <<'EOF'
用法：
  bash scripts/fast_path.sh status
  bash scripts/fast_path.sh branch
  bash scripts/fast_path.sh diffstat
  bash scripts/fast_path.sh files
  bash scripts/fast_path.sh lint
  bash scripts/fast_path.sh test
  bash scripts/fast_path.sh ci
  bash scripts/fast_path.sh ci-watch

说明：
  该脚本只暴露仓库内固定的 Fast Path 模板，不接受任意 shell 片段。
  如果需要更复杂的参数或上下文，请回退到常规命令调用。
EOF
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

pick_python() {
  if [[ -x "${REPO_ROOT}/.venv/bin/python" ]]; then
    printf '%s\n' "${REPO_ROOT}/.venv/bin/python"
  elif command -v python3 >/dev/null 2>&1; then
    command -v python3
  else
    echo "未找到可用的 Python 解释器。" >&2
    exit 1
  fi
}

pick_ruff() {
  if [[ -x "${REPO_ROOT}/.venv/bin/ruff" ]]; then
    printf '%s\n' "${REPO_ROOT}/.venv/bin/ruff"
  elif command -v ruff >/dev/null 2>&1; then
    command -v ruff
  else
    echo "未找到 ruff。请先安装 Ruff 或准备项目虚拟环境。" >&2
    exit 1
  fi
}

cmd="${1}"

case "${cmd}" in
  status)
    git status --short
    ;;
  branch)
    git branch --show-current
    ;;
  diffstat)
    git diff --stat
    ;;
  files)
    rg --files
    ;;
  lint)
    RUFF_BIN="$(pick_ruff)"
    "${RUFF_BIN}" check app/ tests/
    ;;
  test)
    PYTHON_BIN="$(pick_python)"
    "${PYTHON_BIN}" -m pytest tests/ -q
    ;;
  ci)
    bash scripts/check_ci.sh
    ;;
  ci-watch)
    bash scripts/check_ci.sh --watch
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
