"""默认配置 — 对应原 defaults.sh"""
from __future__ import annotations

import platform
from pathlib import Path

# 平台判断只取一次
_SYSTEM: str = platform.system()
IS_WINDOWS: bool = _SYSTEM == "Windows"
IS_MAC: bool = _SYSTEM == "Darwin"
IS_LINUX: bool = _SYSTEM == "Linux"


def _default_downloads() -> Path:
    """默认下载根目录。后续如需平台特化，只改此处。"""
    return Path.home() / "Downloads"


_DOWNLOADS: Path = _default_downloads()

# --- 输出目录默认值 ---
YT_DIR_VIDEO: Path = _DOWNLOADS / "Videos"
YT_DIR_AUDIO: Path = _DOWNLOADS / "Music"
YT_DIR_SUBTITLE: Path = _DOWNLOADS / "Subtitles"
# 默认与视频目录一致；下载播放列表时会按 %(playlist_title)s 建子目录隔离
YT_DIR_PLAYLIST: Path = _DOWNLOADS / "Videos"

# --- 视频排序偏好 ---
YT_PREFER_VIDEO_HEIGHT: int = 1080
YT_PREFER_VIDEO_CODEC: str = "h264"
YT_PREFER_VIDEO_CONTAINER: str = "mp4"

# --- 音频排序偏好 ---
YT_PREFER_AUDIO_CODEC: str = "m4a"
YT_PREFER_AUDIO_MIN_BITRATE: int = 96

# --- 字幕（不可变配置常量）---
YT_PREFER_SUBTITLE_LANGS: tuple[str, ...] = ("zh-Hans", "en")

# --- 行为开关 ---
YT_SHOW_PROGRESS: bool = True
YT_PLAYLIST_CONTINUE_ON_ERROR: bool = True
YT_VALIDATE_FORMATS_BEFORE_MENU: bool = True
YT_VALIDATE_FORMAT_TIMEOUT_SEC: int = 8
YT_VALIDATE_VIDEO_CANDIDATES: int = 4
YT_VALIDATE_AUDIO_CANDIDATES: int = 3
YT_USE_DOWNLOAD_ARCHIVE: bool = True
YT_DOWNLOAD_ARCHIVE: Path = _DOWNLOADS / ".yt-tool-download-archive.txt"
YT_SPONSORBLOCK_DEFAULT_CATEGORIES: tuple[str, ...] = (
    "sponsor",
    "intro",
    "outro",
    "selfpromo",
    "preview",
    "interaction",
)
