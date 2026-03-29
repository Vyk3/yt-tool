#!/bin/zsh
# ================================================================
# yt.command — macOS 薄启动器
#
# 双击即可运行。职责：找到 Python → 启动 app 包 → 转发参数。
# 不做任何业务逻辑，所有核心逻辑在 Python 层。
# ================================================================

set -euo pipefail

# 定位脚本自身所在目录，再向上两级到 yt-tool/
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

find_python() {
    for cmd in python3 python; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "$cmd"
            return 0
        fi
    done
    return 1
}

PYTHON="$(find_python)" || {
    echo "错误: 未找到 Python 解释器"
    echo "请安装 Python 3: brew install python"
    echo ""
    echo "按回车键退出..."
    read -r
    exit 1
}

cd "$PROJECT_DIR"
"$PYTHON" -m app "$@"

echo ""
echo "按回车键退出..."
read -r
