"""根级 conftest：在所有测试收集开始前将 vendor/ 目录注入 sys.path。

app/__init__.py 也做同样的事，但该文件在 pytest 收集阶段运行更早，
确保 wcwidth 等 vendored 包在任何导入路径下都能被找到。
"""
import sys
from pathlib import Path

_VENDOR = Path(__file__).parent / "vendor"
if str(_VENDOR) not in sys.path:
    sys.path.insert(0, str(_VENDOR))
