"""PyInstaller entry point.

`app/__main__.py` uses relative imports which break in a frozen context because
PyInstaller sets __package__ = None when executing the entry script directly.
This wrapper uses absolute imports and is safe to use as the PyInstaller target.

Normal `python -m app` usage continues to go through app/__main__.py unchanged.
"""
import sys
from app.__main__ import main

if __name__ == "__main__":
    sys.exit(main())
