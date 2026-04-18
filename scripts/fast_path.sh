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
  bash scripts/fast_path.sh files [app|tests|scripts|rules|skills|agents]
  bash scripts/fast_path.sh lint
  bash scripts/fast_path.sh test
  bash scripts/fast_path.sh ci [--json]
  bash scripts/fast_path.sh ci-watch [--interval SECONDS] [--timeout SECONDS]

说明：
  该脚本只暴露仓库内固定的 Fast Path 模板，不接受任意 shell 片段。
  如果需要更复杂的参数或上下文，请回退到常规命令调用。
EOF
}

if [[ $# -lt 1 ]]; then
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

require_no_args() {
  local subcmd="${1}"
  shift
  if [[ $# -ne 0 ]]; then
    echo "fast_path: '${subcmd}' 不接受额外参数。" >&2
    exit 2
  fi
}

positive_int() {
  [[ "${1}" =~ ^[1-9][0-9]*$ ]]
}

summarize_status() {
  local output
  output="$(git status --short)"
  if [[ -z "${output}" ]]; then
    echo "[status] clean"
    return 0
  fi

  local count
  count="$(printf '%s\n' "${output}" | sed '/^$/d' | wc -l | tr -d ' ')"
  echo "[status] ${count} path(s) changed"
  printf '%s\n' "${output}"
}

summarize_branch() {
  local branch
  branch="$(git branch --show-current)"
  if [[ -z "${branch}" ]]; then
    echo "[branch] detached"
  else
    echo "[branch] ${branch}"
  fi
}

summarize_diffstat() {
  local output
  output="$(git diff --stat)"
  if [[ -z "${output}" ]]; then
    echo "[diffstat] no unstaged changes"
  else
    echo "[diffstat]"
    printf '%s\n' "${output}"
  fi
}

summarize_files() {
  local prefix="${1:-}"
  local output
  if [[ -n "${prefix}" ]]; then
    output="$(rg --files "${prefix}")"
  else
    output="$(rg --files)"
  fi

  local count
  count="$(printf '%s\n' "${output}" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ -n "${prefix}" ]]; then
    echo "[files] ${count} file(s) under ${prefix}"
  else
    echo "[files] ${count} file(s)"
  fi

  if [[ "${count}" -gt 20 ]]; then
    printf '%s\n' "${output}" | head -20
    echo "... (${count} total)"
  else
    printf '%s\n' "${output}"
  fi
}

run_lint() {
  local ruff_bin
  ruff_bin="$(pick_ruff)"
  local output
  if output="$("${ruff_bin}" check app/ tests/ 2>&1)"; then
    echo "[lint] passed"
  else
    printf '%s\n' "${output}" >&2
    return 1
  fi
}

run_test() {
  local python_bin
  python_bin="$(pick_python)"
  local output
  if output="$("${python_bin}" -m pytest tests/ -q 2>&1)"; then
    local summary
    summary="$(printf '%s\n' "${output}" | tail -1)"
    echo "[test] ${summary}"
  else
    printf '%s\n' "${output}" >&2
    return 1
  fi
}

run_ci() {
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)
        args+=("$1")
        shift
        ;;
      *)
        echo "fast_path: 'ci' 只允许可选参数 --json。" >&2
        exit 2
        ;;
    esac
  done
  bash scripts/check_ci.sh "${args[@]}"
}

run_ci_watch() {
  local interval=""
  local timeout=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --interval)
        [[ $# -ge 2 ]] || { echo "fast_path: --interval 需要一个正整数秒数。" >&2; exit 2; }
        positive_int "$2" || { echo "fast_path: --interval 必须是正整数。" >&2; exit 2; }
        interval="$2"
        shift 2
        ;;
      --timeout)
        [[ $# -ge 2 ]] || { echo "fast_path: --timeout 需要一个正整数秒数。" >&2; exit 2; }
        positive_int "$2" || { echo "fast_path: --timeout 必须是正整数。" >&2; exit 2; }
        timeout="$2"
        shift 2
        ;;
      *)
        echo "fast_path: 'ci-watch' 只允许 --interval N 和 --timeout N。" >&2
        exit 2
        ;;
    esac
  done

  local args=(--watch)
  [[ -n "${interval}" ]] && args+=(--interval "${interval}")
  [[ -n "${timeout}" ]] && args+=(--timeout "${timeout}")
  bash scripts/check_ci.sh "${args[@]}"
}

cmd="${1}"
shift

case "${cmd}" in
  status)
    require_no_args "${cmd}" "$@"
    summarize_status
    ;;
  branch)
    require_no_args "${cmd}" "$@"
    summarize_branch
    ;;
  diffstat)
    require_no_args "${cmd}" "$@"
    summarize_diffstat
    ;;
  files)
    if [[ $# -gt 1 ]]; then
      echo "fast_path: 'files' 最多只允许一个目录参数。" >&2
      exit 2
    fi
    if [[ $# -eq 1 ]]; then
      case "$1" in
        app|tests|scripts|rules|skills|agents)
          summarize_files "$1"
          ;;
        *)
          echo "fast_path: 'files' 只允许 app/tests/scripts/rules/skills/agents。" >&2
          exit 2
          ;;
      esac
    else
      summarize_files
    fi
    ;;
  lint)
    require_no_args "${cmd}" "$@"
    run_lint
    ;;
  test)
    require_no_args "${cmd}" "$@"
    run_test
    ;;
  ci)
    run_ci "$@"
    ;;
  ci-watch)
    run_ci_watch "$@"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
