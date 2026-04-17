#!/usr/bin/env bash

set -euo pipefail

# 这个脚本用于在提交或发起 PR 前，显式执行一次 Python 代码整理。
#
# 它把两类动作收敛到同一个入口里：
# 1. `ruff check --fix`：自动修复 Ruff 能安全处理的问题，例如未使用 import、
#    一部分可机械修复的 lint 问题等。
# 2. `ruff format`：统一代码格式，避免风格差异混进功能性 diff。
#
# 这样的设计有两个目的：
# - 让“修复”和“格式整理”通过一个显式命令完成，而不是依赖编辑时自动触发的 hook。
# - 让 PR 前整理成为可重复、可预期、可审查的步骤。
#
# 默认整理 `app` 和 `tests`；如果你手动传入路径参数，则只处理你指定的目标。

# 无论从哪个目录调用，都先切到仓库根目录，避免相对路径受当前 shell 位置影响。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

# 允许调用者覆盖默认目标：
# - 不传参数时：整理 app 和 tests
# - 传参数时：只整理传入的路径，例如 `scripts/fmt.sh app tests/test_workflow.py`
if [[ "$#" -gt 0 ]]; then
  TARGETS=("$@")
else
  TARGETS=("app" "tests")
fi

# 优先使用项目虚拟环境里的 Ruff，确保与仓库依赖环境一致；
# 如果虚拟环境里没有，再回退到系统 PATH 中的 ruff。
if [[ -x "${REPO_ROOT}/.venv/bin/ruff" ]]; then
  RUFF_CMD=("${REPO_ROOT}/.venv/bin/ruff")
elif command -v ruff >/dev/null 2>&1; then
  RUFF_CMD=("ruff")
else
  echo "未找到 ruff。请先安装 Ruff，或确保 ${REPO_ROOT}/.venv/bin/ruff 可用。" >&2
  exit 1
fi

echo "==> 目标路径: ${TARGETS[*]}"
echo "==> 第一步：执行 ruff check --fix"
"${RUFF_CMD[@]}" check --fix "${TARGETS[@]}"

echo "==> 第二步：执行 ruff format"
"${RUFF_CMD[@]}" format "${TARGETS[@]}"

echo "==> 完成：已执行 fix + format"
