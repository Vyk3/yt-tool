"""main.py 主流程编排测试。"""
from __future__ import annotations

from unittest.mock import MagicMock, patch

from app.cli.main import _retryable_refresh, main


class TestMainFlow:
    def test_missing_url_returns_1(self, monkeypatch):
        """无 URL 时返回 1。"""
        monkeypatch.setattr("builtins.input", lambda _: "")
        result = main([])
        assert result == 1

    def test_detect_failure_returns_1(self, monkeypatch):
        """探测失败时返回 1。"""
        monkeypatch.setattr("builtins.input", lambda _: "0")  # Cookie 询问回答"不使用"
        with patch("app.services.workflow.detect", side_effect=RuntimeError("ERROR")):
            result = main(["http://bad-url"])
            assert result == 1

    def test_user_exits_returns_0(self, monkeypatch, sample_detect_result):
        """用户在下载类型菜单选 0 退出，返回 0。"""
        with patch("app.cli.main._run_env_check", return_value=(True, True)), \
             patch("app.services.workflow.detect", return_value=sample_detect_result), \
             patch("app.services.workflow.validate_detected_formats", return_value=sample_detect_result):
            monkeypatch.setattr("builtins.input", lambda _: "0")
            result = main(["http://example.com"])
            assert result == 0

    def test_audio_download_flow(self, monkeypatch, tmp_path, sample_detect_result):
        """音频下载完整流程。"""
        dl_result = MagicMock(ok=True, output="done", error="", saved_path=str(tmp_path / "x.m4a"))

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

        with patch("app.cli.main._run_env_check", return_value=(True, True)), \
             patch("app.services.workflow.detect", return_value=sample_detect_result), \
             patch("app.services.workflow.validate_detected_formats", return_value=sample_detect_result), \
             patch("app.services.workflow.download_audio", return_value=dl_result):
            result = main(["http://example.com"])
            assert result == 0

    def test_prevalidate_formats_before_menu(self, monkeypatch, sample_detect_result):
        with patch("app.cli.main._run_env_check", return_value=(True, True)), \
             patch("app.services.workflow.detect", return_value=sample_detect_result), \
             patch("app.services.workflow.validate_detected_formats") as mock_validate:
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

        with patch("app.cli.main._run_env_check", return_value=(True, True)), \
             patch("app.services.workflow.detect", return_value=sample_detect_result), \
             patch("app.services.workflow.validate_detected_formats", return_value=sample_detect_result), \
             patch("app.services.workflow.download_video", return_value=fake_result) as mock_download:
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

        with patch("app.cli.main._run_env_check", return_value=(True, True)), \
             patch("app.services.workflow.detect", side_effect=[sample_detect_result, refreshed_info]), \
             patch("app.services.workflow.validate_detected_formats", side_effect=[sample_detect_result, refreshed_info]), \
             patch("app.services.workflow.download_audio", side_effect=[fail_result, ok_result]) as mock_download:
            result = main(["http://example.com"])
            assert result == 0
            assert mock_download.call_count == 2


class TestRetryableRefresh:
    def test_returns_refreshed_info_on_first_format_error(self, sample_detect_result):
        with patch("app.cli.main._refresh_detect_info", return_value=sample_detect_result) as mock_refresh:
            refreshed = _retryable_refresh(
                attempt=0,
                error="Requested format is not available",
                workflow=MagicMock(),
                url="http://example.com",
                has_formats=lambda info: bool(info.audio_formats),
            )
        assert refreshed is sample_detect_result
        mock_refresh.assert_called_once()

    def test_returns_none_when_refreshed_info_has_no_usable_formats(self, sample_detect_result):
        empty_audio = sample_detect_result.__class__(
            title=sample_detect_result.title,
            raw_json=sample_detect_result.raw_json,
            video_formats=sample_detect_result.video_formats,
            audio_formats=(),
            subtitles=sample_detect_result.subtitles,
            auto_subtitles=sample_detect_result.auto_subtitles,
            is_playlist=sample_detect_result.is_playlist,
            playlist_title=sample_detect_result.playlist_title,
            playlist_count=sample_detect_result.playlist_count,
        )
        with patch("app.cli.main._refresh_detect_info", return_value=empty_audio):
            refreshed = _retryable_refresh(
                attempt=0,
                error="Requested format is not available",
                workflow=MagicMock(),
                url="http://example.com",
                has_formats=lambda info: bool(info.audio_formats),
            )
        assert refreshed is None
