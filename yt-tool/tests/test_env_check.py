"""env_check.py 单元测试。"""
from __future__ import annotations

from unittest.mock import patch

from app.core.env_check import CheckResult, check_env


class TestCheckEnv:
    def test_all_found(self):
        """正常环境下 python 和 yt-dlp 应该都能找到。"""
        result = check_env()
        # python 必然存在
        python_item = next(i for i in result.items if i.name == "python")
        assert python_item.found is True

    def test_missing_required_sets_fatal(self):
        """mock shutil.which 让 yt-dlp 找不到。"""
        original_which = __import__("shutil").which

        def fake_which(cmd):
            if cmd == "yt-dlp":
                return None
            return original_which(cmd)

        with patch("app.core.env_check.shutil.which", side_effect=fake_which):
            result = check_env()
            assert result.fatal_missing is True
            assert result.ok is False
            ytdlp = next(i for i in result.items if i.name == "yt-dlp")
            assert ytdlp.found is False

    def test_missing_optional_sets_warning(self):
        """mock shutil.which 让 ffmpeg 找不到。"""
        original_which = __import__("shutil").which

        def fake_which(cmd):
            if cmd == "ffmpeg":
                return None
            return original_which(cmd)

        with patch("app.core.env_check.shutil.which", side_effect=fake_which):
            result = check_env()
            assert result.warning_missing is True
            # 只要 python/yt-dlp 在，ok 仍为 True
            if all(
                i.found for i in result.items if i.required
            ):
                assert result.ok is True

    def test_hint_not_empty(self):
        result = check_env()
        for item in result.items:
            assert item.hint  # 每个依赖都应有安装提示
