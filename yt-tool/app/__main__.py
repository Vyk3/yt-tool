"""允许 python -m app 直接启动。"""
import sys

from .cli.main import main

sys.exit(main())
