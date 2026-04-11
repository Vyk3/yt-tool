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

    def test_detect_failure_returns_1(self, monkeypatch):
        """探测失败时返回 1。"""
        monkeypatch.setattr("builtins.input", lambda _: "0")  # Cookie 询问回答"不使用"
        fake = MagicMock()
        fake.returncode = 1
        fake.stderr = "ERROR"
        with patch("app.format_detector.subprocess.run", return_value=fake):
            result = main(["http://bad-url"])
            assert result == 1

    def test_user_exits_returns_0(self, monkeypatch):
        """用户在下载类型菜单选 0 退出，返回 0。"""
        detect_proc = _mock_detect_success()

        with patch("app.main._run_env_check", return_value=(True, True)), \
             patch("app.format_detector.subprocess.run", return_value=detect_proc):
            monkeypatch.setattr("builtins.input", lambda _: "0")
            result = main(["http://example.com"])
            assert result == 0

    def test_audio_download_flow(self, monkeypatch, tmp_path):
        """音频下载完整流程。"""
        detect_proc = _mock_detect_success()
        dl_proc = MagicMock(returncode=0, stdout="done", stderr="")

        inputs = iter([
            "0",            # Cookie 询问：不使用
            "2",            # 选音频
            "1",            # 选第一个音频流
            "",             # 不下载片段
            "1",            # 不使用 SponsorBlock
            "1",            # 转码询问：保持原始
            str(tmp_path),  # 目录
        ])
        monkeypatch.setattr("builtins.input", lambda _: next(inputs))

        def route_subprocess(*args, **kwargs):
            cmd = args[0] if args else kwargs.get("args", [])
            if "-J" in cmd:
                return detect_proc
            return dl_proc

        with patch("app.main._run_env_check", return_value=(True, True)), \
             patch("subprocess.run", side_effect=route_subprocess):
            result = main(["http://example.com"])
            assert result == 0

    def test_prevalidate_formats_before_menu(self, monkeypatch):
        detect_proc = _mock_detect_success()

        with patch("app.main._run_env_check", return_value=(True, True)), \
             patch("app.format_detector.subprocess.run", return_value=detect_proc), \
             patch("app.main.validate_detected_formats") as mock_validate:
            mock_validate.side_effect = lambda url, info, **kwargs: info
            monkeypatch.setattr("builtins.input", lambda _: "0")
            result = main(["http://example.com"])
            assert result == 0
            mock_validate.assert_called_once()

    def test_video_flow_passes_sections_and_sponsorblock(self, monkeypatch, tmp_path, sample_detect_result):
        inputs = iter([
            "0",               # Cookie
            "1",               # 下载视频
            "*10:15-20:30",    # 片段
            "3",               # SponsorBlock remove
            "",                # SponsorBlock 默认类别
            "1",               # 第一个视频流
            "0",               # 不嵌入字幕
            str(tmp_path),     # 目录
        ])
        monkeypatch.setattr("builtins.input", lambda _: next(inputs))

        fake_result = MagicMock(ok=True, output="ok", error="", saved_path=str(tmp_path / "x.mp4"))

        with patch("app.main._run_env_check", return_value=(True, True)), \
             patch("app.main.detect", return_value=sample_detect_result), \
             patch("app.main.validate_detected_formats", return_value=sample_detect_result), \
             patch("app.main.download_video", return_value=fake_result) as mock_download:
            result = main(["http://example.com"])
            assert result == 0
            extra_args = mock_download.call_args.kwargs["extra_args"]
            assert "--download-sections" in extra_args
            assert "*10:15-20:30" in extra_args
            assert "--sponsorblock-remove" in extra_args

    def test_audio_retries_when_format_becomes_unavailable(self, monkeypatch, tmp_path, sample_detect_result):
        refreshed_info = sample_detect_result
        inputs = iter([
            "0",            # Cookie
            "2",            # 音频
            "1",            # 第一次选失效格式
            "",             # 不下载片段
            "1",            # 不使用 SponsorBlock
            "1",            # 保持原始
            str(tmp_path),  # 目录
            "1",            # 重新探测后再次选择
            "",             # 不下载片段
            "1",            # 不使用 SponsorBlock
            "1",            # 保持原始
            str(tmp_path),  # 目录
        ])
        monkeypatch.setattr("builtins.input", lambda _: next(inputs))

        fail_result = MagicMock(ok=False, output="", error="yt-dlp exited 1: Requested format is not available", saved_path="")
        ok_result = MagicMock(ok=True, output="ok", error="", saved_path=str(tmp_path / "x.m4a"))

        with patch("app.main._run_env_check", return_value=(True, True)), \
             patch("app.main.detect", side_effect=[sample_detect_result, refreshed_info]), \
             patch("app.main.validate_detected_formats", side_effect=[sample_detect_result, refreshed_info]), \
             patch("app.main.download_audio", side_effect=[fail_result, ok_result]) as mock_download:
            result = main(["http://example.com"])
            assert result == 0
            assert mock_download.call_count == 2
