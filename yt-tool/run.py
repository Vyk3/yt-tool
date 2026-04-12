"""PyInstaller entry point.

`app/__main__.py` uses relative imports which break in a frozen context because
PyInstaller sets __package__ = None when executing the entry script directly.
This wrapper uses absolute imports and is safe to use as the PyInstaller target.

Normal `python -m app` usage continues to go through app/__main__.py unchanged.
"""
import os
import stat
import sys


def _patch_frozen_path() -> None:
    """Add the PyInstaller bundle dir to PATH so bundled binaries (yt-dlp) are found."""
    if not (getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS")):
        return
    bundle_dir: str = sys._MEIPASS  # type: ignore[attr-defined]
    # Ensure bundled executables have execute permission (PyInstaller may strip it).
    for name in ("yt-dlp", "ffmpeg"):
        path = os.path.join(bundle_dir, name)
        if os.path.isfile(path):
            mode = os.stat(path).st_mode
            os.chmod(path, mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    os.environ["PATH"] = bundle_dir + os.pathsep + os.environ.get("PATH", "")


_patch_frozen_path()

from app.__main__ import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
