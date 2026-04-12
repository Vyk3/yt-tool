"""PyInstaller entry point.

`app/__main__.py` uses relative imports which break in a frozen context because
PyInstaller sets __package__ = None when executing the entry script directly.
This wrapper uses absolute imports and is safe to use as the PyInstaller target.

Normal `python -m app` usage continues to go through app/__main__.py unchanged.
"""
import os
import stat
import sys


def _ensure_executable(bundle_dir: str, binary_base_name: str) -> None:
    """Best-effort chmod for bundled helper binaries."""
    ext = ".exe" if os.name == "nt" else ""
    binary_path = os.path.join(bundle_dir, f"{binary_base_name}{ext}")
    if not os.path.isfile(binary_path):
        return
    mode = os.stat(binary_path).st_mode
    os.chmod(binary_path, mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def _patch_frozen_path() -> None:
    """Add the PyInstaller bundle dir to PATH so bundled binaries are found."""
    if not (getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS")):
        return
    bundle_dir: str = sys._MEIPASS  # type: ignore[attr-defined]
    # Ensure bundled helper binaries keep executable permissions in frozen builds.
    # PyInstaller packaging can strip execute bits on Unix-like targets.
    _ensure_executable(bundle_dir, "yt-dlp")
    _ensure_executable(bundle_dir, "ffmpeg")
    _ensure_executable(bundle_dir, "ffprobe")
    os.environ["PATH"] = bundle_dir + os.pathsep + os.environ.get("PATH", "")


_patch_frozen_path()

from app.__main__ import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
