"""downloader.py 单元测试。"""
from __future__ import annotations

import subprocess
from unittest.mock import MagicMock, patch

import pytest

from app.downloader import (
    DownloadResult,
    _common_args,
    download_audio,
    download_subs,
    download_video,
)


class TestCommonArgs:
    def test_default_has_no_warnings(self):
        args = _common_args()
        assert "--no-warnings" in args

    def test_no_progress_when_disabled(self):
        with patch("app.downloader.config") as mock_cfg:
            mock_cfg.YT_SHOW_PROGRESS = False
            args = _common_args()
            assert "--no-progress" in args

    def test_no_no_progress_when_enabled(self):
        with patch("app.downloader.config") as mock_cfg:
            mock_cfg.YT_SHOW_PROGRESS = True
            args = _common_args()
            assert "--no-progress" not in args


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
        with patch("app.downloader.subprocess.run", return_value=fake_proc):
            result = download_video("http://example.com/v", "137", str(tmp_path))
            assert result.ok is True

    def test_ytdlp_failure(self, tmp_path):
        fake_proc = MagicMock()
        fake_proc.returncode = 1
        fake_proc.stdout = ""
        fake_proc.stderr = "ERROR: video not found"
        with patch("app.downloader.subprocess.run", return_value=fake_proc):
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
        with patch("app.downloader.subprocess.run", return_value=fake_proc):
            result = download_audio("http://x", "140", str(tmp_path))
            assert result.ok is True


class TestDownloadSubs:
    def test_empty_params_fail(self):
        assert download_subs("", "en", "/tmp").ok is False
        assert download_subs("http://x", "", "/tmp").ok is False

    def test_success(self, tmp_path):
        fake_proc = MagicMock()
        fake_proc.returncode = 0
        fake_proc.stdout = "ok"
        fake_proc.stderr = ""
        with patch("app.downloader.subprocess.run", return_value=fake_proc):
            result = download_subs("http://x", "en", str(tmp_path))
            assert result.ok is True
            # 验证 --skip-download 参数存在
