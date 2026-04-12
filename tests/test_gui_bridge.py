"""Tests for pywebview GUI bridge."""
from __future__ import annotations

from pathlib import Path
from unittest.mock import Mock, patch

import pytest

from app.core.env_check import CheckItem, CheckResult
from app.gui.bridge import Api, _serialize
from app.services.models import DetectResponse, TaskResult


class TestSerialize:
    """Test _serialize helper function."""

    def test_serialize_dict_passthrough(self) -> None:
        obj = {"key": "value", "num": 42}
        assert _serialize(obj) == obj

    def test_serialize_string_passthrough(self) -> None:
        obj = "string"
        assert _serialize(obj) == "string"

    def test_serialize_path_to_string(self) -> None:
        obj = Path("/tmp/test")
        assert _serialize(obj) == "/tmp/test"

    def test_serialize_tuple_to_list(self) -> None:
        obj = (1, 2, 3)
        assert _serialize(obj) == [1, 2, 3]

    def test_serialize_nested_tuple(self) -> None:
        obj = ((1, 2), (3, 4))
        result = _serialize(obj)
        assert result == [[1, 2], [3, 4]]

    def test_serialize_dataclass(self) -> None:
        result = TaskResult(
            ok=True,
            state="success",
            output="test output",
            error="",
            saved_path="/path/to/file",
        )
        serialized = _serialize(result)
        assert isinstance(serialized, dict)
        assert serialized["ok"] is True
        assert serialized["state"] == "success"
        assert serialized["output"] == "test output"

    def test_serialize_dataclass_with_path(self) -> None:
        result = TaskResult(
            ok=True,
            state="success",
            output="",
            error="",
            saved_path="/path/to/file",
        )
        serialized = _serialize(result)
        assert serialized["saved_path"] == "/path/to/file"


class TestApi:
    """Test Api bridge class."""

    @pytest.fixture
    def api(self) -> Api:
        return Api()

    def test_init(self, api: Api) -> None:
        assert api._window is None
        assert api._workflow is not None

    def test_set_window(self, api: Api) -> None:
        mock_window = Mock()
        api.set_window(mock_window)
        assert api._window is mock_window

    def test_check_environment(self, api: Api) -> None:
        with patch.object(api._workflow, "check_environment") as mock_check:
            mock_check.return_value = CheckResult(
                ok=True,
                fatal_missing=False,
                warning_missing=False,
                items=(
                    CheckItem("python", True, True, "/usr/bin/python3", ""),
                    CheckItem("yt-dlp", True, True, "/usr/local/bin/yt-dlp", ""),
                    CheckItem("ffmpeg", False, True, "/usr/local/bin/ffmpeg", ""),
                ),
            )
            result = api.check_environment()
            assert isinstance(result, dict)
            assert result["ok"] is True

    def test_detect_formats_empty_url(self, api: Api) -> None:
        result = api.detect_formats("")
        assert result == {"error": "URL 不能为空"}

    def test_detect_formats_none_url(self, api: Api) -> None:
        result = api.detect_formats(None)  # type: ignore[arg-type]
        assert result == {"error": "URL 不能为空"}

    def test_detect_formats_success(self, api: Api) -> None:
        with patch.object(api._workflow, "detect_formats") as mock_detect:
            mock_detect.return_value = DetectResponse(
                title="Test Video",
                video_formats=(),
                audio_formats=(),
                subtitles=(),
                auto_subtitles=(),
            )
            result = api.detect_formats("http://example.com/video")
            assert isinstance(result, dict)
            assert "title" in result
            assert result["title"] == "Test Video"

    def test_detect_formats_error(self, api: Api) -> None:
        with patch.object(api._workflow, "detect_formats") as mock_detect:
            mock_detect.side_effect = ValueError("Format not available")
            result = api.detect_formats("http://example.com/video")
            assert "error" in result
            assert "Format not available" in result["error"]

    def test_start_download_empty_url(self, api: Api) -> None:
        result = api.start_download(
            kind="video",
            url="",
            dest_dir="/tmp",
        )
        assert result == {"ok": False, "error": "URL 不能为空"}

    def test_start_download_none_url(self, api: Api) -> None:
        result = api.start_download(
            kind="video",
            url=None,  # type: ignore[arg-type]
            dest_dir="/tmp",
        )
        assert result == {"ok": False, "error": "URL 不能为空"}

    def test_start_download_success(self, api: Api) -> None:
        with patch.object(api._workflow, "build_download_request"), patch.object(
            api._workflow, "retry_with_redetect"
        ) as mock_download:
            mock_download.return_value = TaskResult(
                ok=True,
                state="success",
                output="Downloaded",
                saved_path="/tmp/video.mp4",
            )
            result = api.start_download(
                kind="video",
                url="http://example.com/video",
                dest_dir="/tmp",
            )
            assert isinstance(result, dict)
            assert result["ok"] is True

    def test_get_default_dirs(self, api: Api) -> None:
        result = api.get_default_dirs()
        assert "video" in result
        assert "audio" in result
        assert "subtitle" in result
        assert isinstance(result["video"], str)
        assert isinstance(result["audio"], str)
        assert isinstance(result["subtitle"], str)

    def test_get_platform(self, api: Api) -> None:
        result = api.get_platform()
        assert result in ("Darwin", "Windows", "Linux")

    def test_browse_directory_no_window(self, api: Api) -> None:
        result = api.browse_directory()
        assert result is None

    def test_browse_directory_with_window(self, api: Api) -> None:
        mock_window = Mock()
        mock_window.create_file_dialog.return_value = ["/chosen/path"]
        api.set_window(mock_window)
        result = api.browse_directory()
        assert result == "/chosen/path"

    def test_browse_directory_cancelled(self, api: Api) -> None:
        mock_window = Mock()
        mock_window.create_file_dialog.return_value = None
        api.set_window(mock_window)
        result = api.browse_directory()
        assert result is None
