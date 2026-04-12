"""downloader.py 单元测试。"""
from __future__ import annotations

import subprocess
from unittest.mock import MagicMock, patch

import pytest

from app.core.downloader import (
    DownloadResult,
    _common_args,
    _run_ytdlp,
    _stream_process_output,
    download_audio,
    download_auto_subs,
    download_playlist,
    download_subs,
    download_video,
)


class TestCommonArgs:
    def test_default_has_no_warnings(self):
        args = _common_args()
        assert "--no-warnings" in args

    def test_no_progress_when_disabled(self):
        with patch("app.core.downloader.config") as mock_cfg:
            mock_cfg.YT_SHOW_PROGRESS = False
            args = _common_args()
            assert "--no-progress" in args

    def test_no_no_progress_when_enabled(self):
        with patch("app.core.downloader.config") as mock_cfg:
            mock_cfg.YT_SHOW_PROGRESS = True
            args = _common_args()
            assert "--no-progress" not in args


class TestRunYtdlp:
    def test_tty_progress_uses_streaming_path(self, monkeypatch):
        monkeypatch.setattr("app.core.downloader.config.YT_SHOW_PROGRESS", True)
        monkeypatch.setattr("app.core.downloader.sys.stdout.isatty", lambda: True)
        with patch("app.core.downloader._stream_process_output", return_value=(0, "[download] Destination: /tmp/x.mp4\n")) as mock_stream:
            result = _run_ytdlp(["http://example.com"])
            assert result.ok is True
            assert result.saved_path == "/tmp/x.mp4"
            mock_stream.assert_called_once_with(["yt-dlp", "http://example.com"], on_chunk=None)

    def test_on_chunk_forces_streaming_in_non_tty(self, monkeypatch):
        """on_chunk 提供时即使非 TTY 也应走流式路径。"""
        monkeypatch.setattr("app.core.downloader.config.YT_SHOW_PROGRESS", False)
        monkeypatch.setattr("app.core.downloader.sys.stdout.isatty", lambda: False)
        chunks: list[str] = []
        with patch("app.core.downloader._stream_process_output", return_value=(0, "ok\n")) as mock_stream:
            result = _run_ytdlp(["http://example.com"], on_chunk=chunks.append)
            assert result.ok is True
            mock_stream.assert_called_once_with(["yt-dlp", "http://example.com"], on_chunk=chunks.append)


class TestDownloadVideo:
    def test_empty_url_fails(self):
        result = download_video("", "137", "/tmp")
        assert result.ok is False
        assert "required" in result.error

    def test_empty_format_fails(self):
        result = download_video("http://example.com", "", "/tmp")
        assert result.ok is False

    def test_success(self, tmp_path):
        fake_proc = MagicMock()
        fake_proc.returncode = 0
        fake_proc.stdout = "downloaded ok"
        fake_proc.stderr = ""
        with patch("app.core.downloader.subprocess.run", return_value=fake_proc):
            result = download_video("http://example.com/v", "137", str(tmp_path))
            assert result.ok is True

    def test_success_extracts_saved_path(self, tmp_path):
        fake_proc = MagicMock()
        fake_proc.returncode = 0
        fake_proc.stdout = '[download] Destination: "/tmp/out.mp4"\n'
        fake_proc.stderr = ""
        with patch("app.core.downloader.subprocess.run", return_value=fake_proc):
            result = download_video("http://example.com/v", "137", str(tmp_path))
            assert result.saved_path == "/tmp/out.mp4"

    def test_embed_subs_adds_required_args(self, tmp_path):
        fake_proc = MagicMock(returncode=0, stdout="ok", stderr="")
        with patch("app.core.downloader.subprocess.run", return_value=fake_proc) as mock_run:
            result = download_video(
                "http://example.com/v",
                "137",
                str(tmp_path),
                embed_subs_lang="en",
            )
            assert result.ok is True
            args = mock_run.call_args.args[0]
            assert "--write-subs" in args
            assert "--embed-subs" in args
            assert "--sub-langs" in args
            assert "en" in args
            assert "--sub-format" in args

    def test_no_download_archive_for_single_video(self, tmp_path):
        """单条视频下载不应使用归档，避免同一视频不同格式/片段被静默跳过。"""
        fake_proc = MagicMock(returncode=0, stdout="ok", stderr="")
        with patch("app.core.downloader.subprocess.run", return_value=fake_proc) as mock_run:
            result = download_video("http://example.com/v", "137", str(tmp_path))
            assert result.ok is True
            args = mock_run.call_args.args[0]
            assert "--download-archive" not in args

    def test_ytdlp_failure(self, tmp_path):
        fake_proc = MagicMock()
        fake_proc.returncode = 1
        fake_proc.stdout = ""
        fake_proc.stderr = "ERROR: video not found"
        with patch("app.core.downloader.subprocess.run", return_value=fake_proc):
            result = download_video("http://example.com/v", "137", str(tmp_path))
            assert result.ok is False
            assert "video not found" in result.error

    def test_bad_dir_fails(self, tmp_path):
        file_path = tmp_path / "afile"
        file_path.write_text("x")
        result = download_video("http://example.com/v", "137", str(file_path))
        assert result.ok is False
        assert "不是目录" in result.error


class TestDownloadAudio:
    def test_empty_params_fail(self):
        assert download_audio("", "140", "/tmp").ok is False
        assert download_audio("http://x", "", "/tmp").ok is False

    def test_success(self, tmp_path):
        fake_proc = MagicMock()
        fake_proc.returncode = 0
        fake_proc.stdout = "ok"
        fake_proc.stderr = ""
        with patch("app.core.downloader.subprocess.run", return_value=fake_proc):
            result = download_audio("http://x", "140", str(tmp_path))
            assert result.ok is True

    def test_transcode_adds_args(self, tmp_path):
        fake_proc = MagicMock(returncode=0, stdout="ok", stderr="")
        with patch("app.core.downloader.subprocess.run", return_value=fake_proc) as mock_run:
            result = download_audio("http://x", "140", str(tmp_path), transcode_to="mp3")
            assert result.ok is True
            args = mock_run.call_args.args[0]
            assert "-x" in args
            assert "--audio-format" in args
            assert "mp3" in args


class TestDownloadSubs:
    def test_empty_params_fail(self):
        assert download_subs("", "en", "/tmp").ok is False
        assert download_subs("http://x", "", "/tmp").ok is False

    def test_success(self, tmp_path):
        fake_proc = MagicMock()
        fake_proc.returncode = 0
        fake_proc.stdout = "ok"
        fake_proc.stderr = ""
        with patch("app.core.downloader.subprocess.run", return_value=fake_proc):
            result = download_subs("http://x", "en", str(tmp_path))
            assert result.ok is True
            # 验证 --skip-download 参数存在

    def test_auto_subs_uses_auto_flag(self, tmp_path):
        fake_proc = MagicMock(returncode=0, stdout="ok", stderr="")
        with patch("app.core.downloader.subprocess.run", return_value=fake_proc) as mock_run:
            result = download_auto_subs("http://x", "en", str(tmp_path))
            assert result.ok is True
            args = mock_run.call_args.args[0]
            assert "--write-auto-subs" in args
            assert "--write-subs" not in args


class TestDownloadPlaylist:
    def test_continue_on_error_config_is_applied(self, tmp_path):
        fake_proc = MagicMock(returncode=0, stdout="ok", stderr="")
        with patch("app.core.downloader.config.YT_PLAYLIST_CONTINUE_ON_ERROR", False), \
             patch("app.core.downloader.subprocess.run", return_value=fake_proc) as mock_run:
            result = download_playlist("http://example.com/list", "video", str(tmp_path))
            assert result.ok is True
            args = mock_run.call_args.args[0]
            assert "--abort-on-error" in args
            assert "--no-abort-on-error" not in args

    def test_extra_args_are_forwarded(self, tmp_path):
        fake_proc = MagicMock(returncode=0, stdout="ok", stderr="")
        with patch("app.core.downloader.subprocess.run", return_value=fake_proc) as mock_run:
            result = download_playlist(
                "http://example.com/list",
                "video",
                str(tmp_path),
                extra_args=["--sponsorblock-mark", "sponsor,intro"],
            )
            assert result.ok is True
            args = mock_run.call_args.args[0]
            assert "--sponsorblock-mark" in args


class TestStreamProcessOutputOnChunk:
    def test_on_chunk_called_instead_of_stdout(self, monkeypatch):
        """on_chunk 提供时调用回调而非写 sys.stdout。"""
        mock_stdout = MagicMock()
        mock_stdout.read.side_effect = ["h", "i", ""]
        mock_proc = MagicMock()
        mock_proc.stdout = mock_stdout
        mock_proc.wait.return_value = 0

        chunks_received: list[str] = []
        stdout_written: list[str] = []
        monkeypatch.setattr("app.core.downloader.sys.stdout.write", lambda s: stdout_written.append(s))

        with patch("app.core.downloader.subprocess.Popen", return_value=mock_proc):
            returncode, output = _stream_process_output(["cmd"], on_chunk=lambda c: chunks_received.append(c))

        assert returncode == 0
        assert output == "hi"
        assert chunks_received == ["h", "i"]
        assert stdout_written == []

    def test_default_writes_stdout(self, monkeypatch):
        """on_chunk=None 时走 sys.stdout.write 路径（CLI 默认行为）。"""
        mock_stdout = MagicMock()
        mock_stdout.read.side_effect = ["x", ""]
        mock_proc = MagicMock()
        mock_proc.stdout = mock_stdout
        mock_proc.wait.return_value = 0

        stdout_written: list[str] = []
        monkeypatch.setattr("app.core.downloader.sys.stdout.write", lambda s: stdout_written.append(s))
        monkeypatch.setattr("app.core.downloader.sys.stdout.flush", lambda: None)

        with patch("app.core.downloader.subprocess.Popen", return_value=mock_proc):
            returncode, output = _stream_process_output(["cmd"])

        assert returncode == 0
        assert output == "x"
        assert stdout_written == ["x"]
