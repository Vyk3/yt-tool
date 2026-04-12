"""允许 `python -m app.gui` 启动 GUI。"""
from __future__ import annotations

import sys

from .main import main

sys.exit(main())
