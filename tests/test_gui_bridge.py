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
            req = mock_detect.call_args.args[0]
            assert req.url == "http://example.com/video"
            assert req.cookies_from is None
            assert req.extra_args == ("--no-playlist",)

    def test_detect_formats_passes_cookies(self, api: Api) -> None:
        with patch.object(api._workflow, "detect_formats") as mock_detect:
            mock_detect.return_value = DetectResponse(
                title="Test Video",
                video_formats=(),
                audio_formats=(),
                subtitles=(),
                auto_subtitles=(),
            )
            api.detect_formats("http://example.com/video", "chrome")
            req = mock_detect.call_args.args[0]
            assert req.cookies_from == "chrome"

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

    def test_start_download_forwards_request_fields(self, api: Api) -> None:
        request_obj = object()
        with patch.object(api._workflow, "build_download_request", return_value=request_obj) as mock_build, patch.object(
            api._workflow, "retry_with_redetect"
        ) as mock_download:
            mock_download.return_value = TaskResult(ok=True, state="success")
            api.start_download(
                kind="subtitle",
                url="http://example.com/video",
                dest_dir="/tmp",
                format_id="137",
                audio_format_id="140",
                subtitle_lang="auto:en",
                transcode_to="mp3",
                cookies_from="chrome",
                extra_args=["--proxy", "socks5://127.0.0.1:1080"],
            )
            mock_build.assert_called_once_with(
                kind="subtitle",
                url="http://example.com/video",
                dest_dir="/tmp",
                format_id="137",
                audio_format_id="140",
                subtitle_lang="auto:en",
                transcode_to="mp3",
                cookies_from="chrome",
                extra_args=("--proxy", "socks5://127.0.0.1:1080"),
            )
            mock_download.assert_called_once()
            assert mock_download.call_args.args[0] is request_obj

    def test_start_download_streams_progress_handles_carriage_returns(self, api: Api) -> None:
        mock_window = Mock()
        api.set_window(mock_window)

        def fake_retry(request: object, on_progress=None):  # type: ignore[no-untyped-def]
            assert on_progress is not None
            on_progress(type("Evt", (), {"message": "\r"})())
            on_progress(type("Evt", (), {"message": "a"})())
            on_progress(type("Evt", (), {"message": "b"})())
            on_progress(type("Evt", (), {"message": "\r"})())
            on_progress(type("Evt", (), {"message": "c"})())
            on_progress(type("Evt", (), {"message": "\n"})())
            on_progress(type("Evt", (), {"message": "d"})())
            on_progress(type("Evt", (), {"message": "\r\n"})())
            on_progress(type("Evt", (), {"message": "e"})())
            return TaskResult(ok=True, state="success")

        with patch.object(api._workflow, "build_download_request", return_value=object()), patch.object(
            api._workflow,
            "retry_with_redetect",
            side_effect=fake_retry,
        ):
            api.start_download(
                kind="video",
                url="http://example.com/video",
                dest_dir="/tmp",
                format_id="137",
                audio_format_id="140",
            )

        payloads = [call.args[0] for call in mock_window.evaluate_js.call_args_list]
        assert payloads == [
            'window._onProgress("ab")',
            'window._onProgress("c")',
            'window._onProgress("d")',
            'window._onProgress("e")',
        ]

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
