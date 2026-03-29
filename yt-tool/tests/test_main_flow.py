"""main.py 主流程编排测试。"""
from __future__ import annotations

import json
from unittest.mock import MagicMock, patch

import pytest

from app.main import main

from .test_format_detector import SAMPLE_YTDLP_JSON


def _mock_detect_success():
    """返回一个 mock subprocess.run，模拟 yt-dlp -J 成功。"""
    fake = MagicMock()
    fake.returncode = 0
    fake.stdout = json.dumps(SAMPLE_YTDLP_JSON)
    fake.stderr = ""
    return fake


class TestMainFlow:
    def test_missing_url_returns_1(self, monkeypatch):
        """无 URL 时返回 1。"""
        monkeypatch.setattr("builtins.input", lambda _: "")
        result = main([])
        assert result == 1

    def test_detect_failure_returns_1(self):
        """探测失败时返回 1。"""
        fake = MagicMock()
        fake.returncode = 1
        fake.stderr = "ERROR"
        with patch("app.format_detector.subprocess.run", return_value=fake):
            result = main(["http://bad-url"])
            assert result == 1

    def test_user_exits_returns_0(self, monkeypatch):
        """用户在下载类型菜单选 0 退出，返回 0。"""
        # mock detect 成功
        detect_proc = _mock_detect_success()
        download_proc = MagicMock(returncode=0, stdout="", stderr="")

        with patch("app.format_detector.subprocess.run", return_value=detect_proc):
            monkeypatch.setattr("builtins.input", lambda _: "0")
            result = main(["http://example.com"])
            assert result == 0

    def test_audio_download_flow(self, monkeypatch, tmp_path):
        """音频下载完整流程。"""
        detect_proc = _mock_detect_success()
        dl_proc = MagicMock(returncode=0, stdout="done", stderr="")

        inputs = iter([
            "2",    # 选音频
            "1",    # 选第一个音频流
            str(tmp_path),  # 目录
        ])
        monkeypatch.setattr("builtins.input", lambda _: next(inputs))

        def route_subprocess(*args, **kwargs):
            cmd = args[0] if args else kwargs.get("args", [])
            if "-J" in cmd:
                return detect_proc
            return dl_proc

        with patch("subprocess.run", side_effect=route_subprocess):
            result = main(["http://example.com"])
            assert result == 0
