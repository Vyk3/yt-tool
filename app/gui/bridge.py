"""pywebview JavaScript-Python bridge."""
from __future__ import annotations

import json
import platform
from dataclasses import asdict
from pathlib import Path
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:  # pragma: no cover
    import webview

from ..core import config
from ..services.models import DetectRequest, ProgressEvent
from ..services.workflow import AppWorkflow


def _serialize(obj: Any) -> Any:
    """Convert dataclass instances to dicts for JSON serialization."""
    if hasattr(obj, '__dataclass_fields__'):
        return {k: _serialize(v) for k, v in asdict(obj).items()}
    if isinstance(obj, tuple):
        return [_serialize(i) for i in obj]
    if isinstance(obj, Path):
        return str(obj)
    return obj


class Api:
    """Exposed to JavaScript via pywebview.api."""

    def __init__(self) -> None:
        self._workflow = AppWorkflow()
        self._window: Any | None = None

    def set_window(self, window: webview.Window) -> None:
        self._window = window

    def check_environment(self) -> dict:  # type: ignore[type-arg]
        result = self._workflow.check_environment()
        return _serialize(result)  # type: ignore[return-value]

    def detect_formats(self, url: str, cookies_from: str | None = None) -> dict:  # type: ignore[type-arg]
        if not url:
            return {"error": "URL 不能为空"}
        req = DetectRequest(
            url=url,
            cookies_from=cookies_from or None,
            extra_args=("--no-playlist",),
            validate_formats=False,
        )
        try:
            resp = self._workflow.detect_formats(req)
            return _serialize(resp)  # type: ignore[return-value]
        except (RuntimeError, ValueError) as e:
            return {"error": str(e)}

    def start_download(
        self,
        kind: str,
        url: str,
        dest_dir: str,
        format_id: str = "",
        audio_format_id: str = "",
        subtitle_lang: str = "",
        transcode_to: str = "",
        cookies_from: str | None = None,
        extra_args: list[str] | None = None,
    ) -> dict:  # type: ignore[type-arg]
        if not url:
            return {"ok": False, "error": "URL 不能为空"}

        request = self._workflow.build_download_request(
            kind=kind,  # type: ignore[arg-type]
            url=url,
            dest_dir=dest_dir,
            format_id=format_id,
            audio_format_id=audio_format_id,
            subtitle_lang=subtitle_lang,
            transcode_to=transcode_to,
            cookies_from=cookies_from or None,
            extra_args=tuple(extra_args or []),
        )

        progress_buffer = ""
        skip_lf_after_cr = False

        def emit_progress(message: str) -> None:
            if self._window:
                payload = json.dumps(message)
                self._window.evaluate_js(f"window._onProgress({payload})")

        def on_progress(event: ProgressEvent) -> None:
            nonlocal progress_buffer, skip_lf_after_cr
            for char in event.message:
                if char == "\r":
                    if progress_buffer:
                        emit_progress(progress_buffer)
                    progress_buffer = ""
                    skip_lf_after_cr = True
                elif char == "\n":
                    if skip_lf_after_cr:
                        skip_lf_after_cr = False
                        continue
                    if progress_buffer:
                        emit_progress(progress_buffer)
                    progress_buffer = ""
                else:
                    skip_lf_after_cr = False
                    progress_buffer += char

        result = self._workflow.retry_with_redetect(request, on_progress=on_progress)
        if progress_buffer:
            emit_progress(progress_buffer)
        return _serialize(result)  # type: ignore[return-value]

    def browse_directory(self, current: str = "") -> str | None:
        if not self._window:
            return None
        try:
            import webview as runtime_webview
            folder_dialog = runtime_webview.FOLDER_DIALOG
        except ModuleNotFoundError:
            # CI/unit tests may import bridge without GUI extras installed.
            folder_dialog = 1
        result = self._window.create_file_dialog(
            folder_dialog,
            directory=current or str(Path.home() / "Downloads"),
        )
        if result and len(result) > 0:
            return str(result[0])
        return None

    def get_default_dirs(self) -> dict:  # type: ignore[type-arg]
        return {
            "video": str(config.YT_DIR_VIDEO),
            "audio": str(config.YT_DIR_AUDIO),
            "subtitle": str(config.YT_DIR_SUBTITLE),
        }

    def get_platform(self) -> str:
        return platform.system()
