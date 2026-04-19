"""AppWorkflow 单元测试。"""
from __future__ import annotations

from unittest.mock import patch

import pytest

from app.core.downloader import DownloadResult
from app.core.env_check import CheckResult
from app.services.models import (
    DetectRequest,
    DownloadKind,
    DownloadRequest,
    ProgressEvent,
    TaskResult,
)
from app.services.workflow import AppWorkflow, _is_format_unavailable_error

# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

def _make_dl_result(ok: bool, error: str = "", saved_path: str = "") -> DownloadResult:
    return DownloadResult(ok=ok, output="ok" if ok else "", error=error, saved_path=saved_path)


# ---------------------------------------------------------------------------
# _is_format_unavailable_error
# ---------------------------------------------------------------------------

class TestIsFormatUnavailableError:
    @pytest.mark.parametrize("msg", [
        "yt-dlp exited 1: Requested format is not available",
        "format is not available",
        "REQUESTED FORMAT IS NOT AVAILABLE",
    ])
    def test_recognises_format_errors(self, msg: str):
        assert _is_format_unavailable_error(msg) is True

    def test_ignores_other_errors(self):
        assert _is_format_unavailable_error("network timeout") is False
        assert _is_format_unavailable_error("") is False


# ---------------------------------------------------------------------------
# check_environment
# ---------------------------------------------------------------------------

class TestCheckEnvironment:
    def test_delegates_to_check_env(self):
        mock_result = CheckResult(ok=True, fatal_missing=False, warning_missing=False, items=())
        with patch("app.services.workflow.check_env", return_value=mock_result) as mock:
            result = AppWorkflow().check_environment()
        assert result is mock_result
        mock.assert_called_once_with()

    def test_returns_check_result_unchanged(self):
        failing = CheckResult(ok=False, fatal_missing=True, warning_missing=False, items=())
        with patch("app.services.workflow.check_env", return_value=failing):
            result = AppWorkflow().check_environment()
        assert result.ok is False
        assert result.fatal_missing is True


# ---------------------------------------------------------------------------
# detect_formats
# ---------------------------------------------------------------------------

class TestDetectFormats:
    def test_returns_detect_response(self, sample_detect_result):
        with patch("app.services.workflow.detect", return_value=sample_detect_result), \
             patch("app.services.workflow.validate_detected_formats", return_value=sample_detect_result):
            resp = AppWorkflow().detect_formats(DetectRequest(url="http://example.com"))
        assert resp.title == "Test Video Title"
        assert len(resp.video_formats) == 3
        assert len(resp.audio_formats) == 2

    def test_passes_cookies_to_detect(self, sample_detect_result):
        with patch("app.services.workflow.detect", return_value=sample_detect_result) as mock_detect, \
             patch("app.services.workflow.validate_detected_formats", return_value=sample_detect_result):
            AppWorkflow().detect_formats(DetectRequest(url="http://x.com", cookies_from="chrome"))
        assert mock_detect.call_args.kwargs.get("cookies_from") == "chrome"

    def test_no_playlist_extra_arg_is_forwarded(self, sample_detect_result):
        """extra_args 含 --no-playlist 时 detect() 应收到 no_playlist=True。"""
        with patch("app.services.workflow.detect", return_value=sample_detect_result) as mock_detect, \
             patch("app.services.workflow.validate_detected_formats", return_value=sample_detect_result):
            AppWorkflow().detect_formats(DetectRequest(url="http://x.com", extra_args=("--no-playlist",)))
        assert mock_detect.call_args.kwargs.get("no_playlist") is True

    def test_playlist_fields_propagated(self, sample_detect_result):
        from dataclasses import replace
        playlist_result = replace(
            sample_detect_result,
            is_playlist=True,
            playlist_title="My Playlist",
            playlist_count=5,
        )
        with patch("app.services.workflow.detect", return_value=playlist_result), \
             patch("app.services.workflow.validate_detected_formats", return_value=playlist_result):
            resp = AppWorkflow().detect_formats(DetectRequest(url="http://x.com/list"))
        assert resp.is_playlist is True
        assert resp.playlist_title == "My Playlist"
        assert resp.playlist_count == 5

    def test_validate_formats_false_skips_prevalidation(self, sample_detect_result):
        with patch("app.services.workflow.detect", return_value=sample_detect_result), \
             patch("app.services.workflow.validate_detected_formats") as mock_validate:
            resp = AppWorkflow().detect_formats(
                DetectRequest(url="http://x.com", validate_formats=False)
            )
        assert resp.title == sample_detect_result.title
        mock_validate.assert_not_called()


# ---------------------------------------------------------------------------
# run_download
# ---------------------------------------------------------------------------

class TestRunDownload:
    def test_download_request_accepts_legacy_string_kind(self, tmp_path):
        req = DownloadRequest(kind="audio", url="http://x.com", dest_dir=str(tmp_path), format_id="140")
        assert req.kind == DownloadKind.AUDIO

    def test_invalid_kind_returns_structured_error(self, tmp_path):
        req = DownloadRequest(kind="invalid-kind", url="http://x.com", dest_dir=str(tmp_path))
        result = AppWorkflow().run_download(req)
        assert result.ok is False
        assert result.state == "error"
        assert "Unknown kind" in result.error

    def test_audio_download_success(self, tmp_path):
        fake = _make_dl_result(ok=True, saved_path=str(tmp_path / "x.m4a"))
        with patch("app.services.workflow.download_audio", return_value=fake):
            req = DownloadRequest(kind="audio", url="http://x.com", dest_dir=str(tmp_path), format_id="140")
            result = AppWorkflow().run_download(req)
        assert result.ok is True
        assert result.state == "success"
        assert result.saved_path == str(tmp_path / "x.m4a")

    def test_video_download_merges_audio_format(self, tmp_path):
        fake = _make_dl_result(ok=True)
        with patch("app.services.workflow.download_video", return_value=fake) as mock_dl:
            req = DownloadRequest(
                kind="video", url="http://x.com", dest_dir=str(tmp_path),
                format_id="248", audio_format_id="140",
            )
            AppWorkflow().run_download(req)
        called_fmt = mock_dl.call_args.args[1]
        assert called_fmt == "248+140"

    def test_video_without_audio_format_id(self, tmp_path):
        fake = _make_dl_result(ok=True)
        with patch("app.services.workflow.download_video", return_value=fake) as mock_dl:
            req = DownloadRequest(kind="video", url="http://x.com", dest_dir=str(tmp_path), format_id="137")
            AppWorkflow().run_download(req)
        assert mock_dl.call_args.args[1] == "137"

    def test_subtitle_auto_prefix_routes_to_auto_subs(self, tmp_path):
        fake = _make_dl_result(ok=True)
        with patch("app.services.workflow.download_auto_subs", return_value=fake) as mock_auto, \
             patch("app.services.workflow.download_subs") as mock_subs:
            req = DownloadRequest(
                kind="subtitle", url="http://x.com", dest_dir=str(tmp_path),
                subtitle_lang="auto:en",
            )
            AppWorkflow().run_download(req)
        mock_auto.assert_called_once()
        mock_subs.assert_not_called()
        assert mock_auto.call_args.args[1] == "en"  # "auto:" stripped

    def test_on_progress_receives_events(self, tmp_path):
        """on_progress 回调应收到每个 chunk 对应的 ProgressEvent。"""
        events: list[ProgressEvent] = []

        def fake_audio(url, fmt, dest, *, on_chunk=None, **kwargs):
            if on_chunk:
                on_chunk("chunk1")
                on_chunk("chunk2")
            return _make_dl_result(ok=True)

        with patch("app.services.workflow.download_audio", side_effect=fake_audio):
            req = DownloadRequest(kind="audio", url="http://x.com", dest_dir=str(tmp_path), format_id="140")
            AppWorkflow().run_download(req, on_progress=events.append)

        assert len(events) == 2
        assert all(isinstance(e, ProgressEvent) for e in events)
        assert events[0].stage == "download"
        assert events[0].message == "chunk1"
        assert events[1].message == "chunk2"

    def test_on_progress_none_does_not_pass_on_chunk(self, tmp_path):
        """on_progress=None 时不传 on_chunk，走 CLI 默认 stdout 路径。"""
        with patch("app.services.workflow.download_audio", return_value=_make_dl_result(ok=True)) as mock_dl:
            req = DownloadRequest(kind="audio", url="http://x.com", dest_dir=str(tmp_path), format_id="140")
            AppWorkflow().run_download(req, on_progress=None)
        assert mock_dl.call_args.kwargs.get("on_chunk") is None

    def test_failure_state_is_error(self, tmp_path):
        fake = _make_dl_result(ok=False, error="network error")
        with patch("app.services.workflow.download_audio", return_value=fake):
            req = DownloadRequest(kind="audio", url="http://x.com", dest_dir=str(tmp_path), format_id="140")
            result = AppWorkflow().run_download(req)
        assert result.ok is False
        assert result.state == "error"
        assert result.error == "network error"


# ---------------------------------------------------------------------------
# retry_with_redetect
# ---------------------------------------------------------------------------

class TestRetryWithRedetect:
    def test_retries_on_format_unavailable(self, tmp_path, sample_detect_result):
        fail = TaskResult(ok=False, state="error", error="yt-dlp exited 1: Requested format is not available")
        ok = TaskResult(ok=True, state="success", output="ok", saved_path=str(tmp_path / "x.m4a"))
        calls: list[int] = []

        def fake_run(req, on_progress=None):
            calls.append(1)
            return fail if len(calls) == 1 else ok

        workflow = AppWorkflow()
        with patch.object(workflow, "run_download", side_effect=fake_run), \
             patch("app.services.workflow.detect", return_value=sample_detect_result):
            req = DownloadRequest(kind="audio", url="http://x.com", dest_dir=str(tmp_path), format_id="140")
            result = workflow.retry_with_redetect(req)

        assert result.ok is True
        assert len(calls) == 2

    def test_no_retry_on_other_errors(self, tmp_path):
        fail = TaskResult(ok=False, state="error", error="network timeout")
        workflow = AppWorkflow()
        with patch.object(workflow, "run_download", return_value=fail):
            req = DownloadRequest(kind="audio", url="http://x.com", dest_dir=str(tmp_path), format_id="140")
            result = workflow.retry_with_redetect(req)
        assert result.ok is False
        assert result.error == "network timeout"

    def test_no_retry_if_redetect_fails(self, tmp_path):
        fail = TaskResult(ok=False, state="error", error="Requested format is not available")
        calls: list[int] = []

        def fake_run(req, on_progress=None):
            calls.append(1)
            return fail

        workflow = AppWorkflow()
        with patch.object(workflow, "run_download", side_effect=fake_run), \
             patch("app.services.workflow.detect", side_effect=RuntimeError("detect failed")):
            req = DownloadRequest(kind="audio", url="http://x.com", dest_dir=str(tmp_path), format_id="140")
            result = workflow.retry_with_redetect(req)

        assert result.ok is False
        assert len(calls) == 1  # no second attempt

    def test_no_retry_if_format_gone_after_redetect(self, tmp_path, sample_detect_result):
        """重新探测后若请求的 format_id 不在新结果中，不做无用重试。"""
        from dataclasses import replace as dc_replace
        # 从新探测结果中移除 "140"（只保留 "251"）
        new_audio = tuple(f for f in sample_detect_result.audio_formats if f.id != "140")
        refreshed = dc_replace(sample_detect_result, audio_formats=new_audio)

        fail = TaskResult(ok=False, state="error", error="Requested format is not available")
        calls: list[int] = []

        def fake_run(req, on_progress=None):
            calls.append(1)
            return fail

        workflow = AppWorkflow()
        with patch.object(workflow, "run_download", side_effect=fake_run), \
             patch("app.services.workflow.detect", return_value=refreshed):
            req = DownloadRequest(kind="audio", url="http://x.com", dest_dir=str(tmp_path), format_id="140")
            result = workflow.retry_with_redetect(req)

        assert result.ok is False
        assert len(calls) == 1  # format gone, no second attempt

    def test_no_retry_if_audio_format_gone_after_redetect(self, tmp_path, sample_detect_result):
        """video+audio 合并时 audio_format_id 消失也应跳过重试。"""
        from dataclasses import replace as dc_replace
        # 移除 audio format "140"
        new_audio = tuple(f for f in sample_detect_result.audio_formats if f.id != "140")
        refreshed = dc_replace(sample_detect_result, audio_formats=new_audio)

        fail = TaskResult(ok=False, state="error", error="Requested format is not available")
        calls: list[int] = []

        def fake_run(req, on_progress=None):
            calls.append(1)
            return fail

        workflow = AppWorkflow()
        with patch.object(workflow, "run_download", side_effect=fake_run), \
             patch("app.services.workflow.detect", return_value=refreshed):
            req = DownloadRequest(
                kind="video", url="http://x.com", dest_dir=str(tmp_path),
                format_id="248", audio_format_id="140",
            )
            result = workflow.retry_with_redetect(req)

        assert result.ok is False
        assert len(calls) == 1  # audio gone, no second attempt

    def test_settings_cookies_used_as_fallback(self, tmp_path):
        """request.cookies_from=None 时应使用 AppSettings.cookies_from。"""
        from app.services.models import AppSettings
        settings = AppSettings(
            download_dir_video="/v", download_dir_audio="/a",
            download_dir_subtitle="/s", cookies_from="firefox",
        )
        workflow = AppWorkflow(settings=settings)
        fake = _make_dl_result(ok=True)
        with patch("app.services.workflow.download_audio", return_value=fake) as mock_dl:
            req = DownloadRequest(
                kind="audio", url="http://x.com", dest_dir=str(tmp_path),
                format_id="140",  # cookies_from omitted → None
            )
            workflow.run_download(req)
        assert mock_dl.call_args.kwargs.get("cookies_from") == "firefox"

    def test_per_request_cookies_override_settings(self, tmp_path):
        """per-request cookies_from 应优先于 AppSettings.cookies_from。"""
        from app.services.models import AppSettings
        settings = AppSettings(
            download_dir_video="/v", download_dir_audio="/a",
            download_dir_subtitle="/s", cookies_from="firefox",
        )
        workflow = AppWorkflow(settings=settings)
        fake = _make_dl_result(ok=True)
        with patch("app.services.workflow.download_audio", return_value=fake) as mock_dl:
            req = DownloadRequest(
                kind="audio", url="http://x.com", dest_dir=str(tmp_path),
                format_id="140", cookies_from="chrome",
            )
            workflow.run_download(req)
        assert mock_dl.call_args.kwargs.get("cookies_from") == "chrome"

    def test_playlist_retry_not_gated_by_format_id(self, tmp_path, sample_detect_result):
        """playlist kind 的 format_id 是模式字符串，不应被可用性检查拦截。"""
        fail = TaskResult(ok=False, state="error", error="Requested format is not available")
        ok = TaskResult(ok=True, state="success", output="ok")
        calls: list[int] = []

        def fake_run(req, on_progress=None):
            calls.append(1)
            return fail if len(calls) == 1 else ok

        workflow = AppWorkflow()
        with patch.object(workflow, "run_download", side_effect=fake_run), \
             patch("app.services.workflow.detect", return_value=sample_detect_result):
            req = DownloadRequest(
                kind="playlist", url="http://x.com/list", dest_dir=str(tmp_path),
                format_id="video",  # 模式字符串，不是真实格式 ID
            )
            result = workflow.retry_with_redetect(req)

        assert result.ok is True
        assert len(calls) == 2  # 应该重试

    def test_no_playlist_passed_to_detect_when_in_extra_args(self, tmp_path, sample_detect_result):
        """extra_args 含 --no-playlist 时应透传给 detect()。"""
        fail = TaskResult(ok=False, state="error", error="Requested format is not available")

        def fake_run(req, on_progress=None):
            return fail

        workflow = AppWorkflow()
        with patch.object(workflow, "run_download", side_effect=fake_run), \
             patch("app.services.workflow.detect", return_value=sample_detect_result) as mock_detect:
            req = DownloadRequest(
                kind="audio", url="http://x.com", dest_dir=str(tmp_path),
                format_id="140", extra_args=("--no-playlist",),
            )
            workflow.retry_with_redetect(req)

        assert mock_detect.call_args.kwargs.get("no_playlist") is True
