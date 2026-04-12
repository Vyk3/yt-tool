from __future__ import annotations

import importlib
import sys
from types import ModuleType

from app.core import config
from app.services.models import AppSettings, DownloadRequest, ProgressEvent, TaskResult


def _make_fake_pyside6():
    class _Signal:
        def __init__(self, *args, **kwargs):
            self._callbacks = []

        def connect(self, cb):
            self._callbacks.append(cb)

        def emit(self, *args, **kwargs):
            for cb in list(self._callbacks):
                cb(*args, **kwargs)

    class _QObject:
        def __init__(self, parent=None):
            self._parent = parent

        def moveToThread(self, thread):
            self._thread = thread

        def deleteLater(self):
            return None

    class _QThread(_QObject):
        def __init__(self, parent=None):
            super().__init__(parent)
            self.finished = _Signal()

        def start(self):
            # Workers are QThread subclasses; start() must invoke run() directly.
            self.run()
            self.finished.emit()

        def wait(self, msecs=None):
            return True

        def quit(self):
            return None

    def _slot(*args, **kwargs):
        def decorator(func):
            return func

        return decorator

    qtcore = ModuleType("PySide6.QtCore")
    qtcore.QObject = _QObject
    qtcore.QThread = _QThread
    qtcore.Signal = _Signal
    qtcore.Slot = _slot

    pyside6 = ModuleType("PySide6")
    pyside6.QtCore = qtcore

    return pyside6, qtcore


def _load_gui_modules(monkeypatch):
    pyside6 = sys.modules.get("PySide6")
    qtcore = sys.modules.get("PySide6.QtCore")
    if pyside6 is None or qtcore is None:
        pyside6, qtcore = _make_fake_pyside6()
    monkeypatch.setitem(sys.modules, "PySide6", pyside6)
    monkeypatch.setitem(sys.modules, "PySide6.QtCore", qtcore)
    controllers = importlib.import_module("app.gui.controllers")
    workers = importlib.import_module("app.gui.workers")
    importlib.reload(workers)
    importlib.reload(controllers)
    return controllers, workers


class _FakeWindow:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.logs: list[str] = []
        self.url = "http://example.com/v"
        self.cookies = "chrome"
        self.kind = "video"
        self.extra_args = ("--no-playlist",)
        self.download_sections = "*00:00:10-00:00:20"
        self.sponsorblock_mode = "remove"
        self.sponsorblock_categories = "sponsor,selfpromo"
        self.video_id = "137"
        self.audio_id = "140"
        self.subtitle = "auto:en"
        self.playlist_mode = "audio"
        self.transcode = "mp3"

    def current_url(self) -> str:
        return self.url

    def current_cookies_from(self):
        return self.cookies

    def current_download_kind(self) -> str:
        return self.kind

    def current_extra_args(self):
        return self.extra_args

    def current_download_sections(self):
        return self.download_sections

    def current_sponsorblock_mode(self):
        return self.sponsorblock_mode

    def current_sponsorblock_categories(self):
        return self.sponsorblock_categories

    def selected_video_format_id(self) -> str:
        return self.video_id

    def selected_audio_format_id(self) -> str:
        return self.audio_id

    def selected_subtitle_lang(self) -> str:
        return self.subtitle

    def current_playlist_mode(self) -> str:
        return self.playlist_mode

    def current_transcode_to(self) -> str:
        return self.transcode

    def show_error(self, msg: str) -> None:
        self.errors.append(msg)

    def append_log(self, msg: str) -> None:
        self.logs.append(msg)

    def show_result(self, path: str) -> None:
        self.logs.append(f"DONE:{path}")

    def set_detecting_status(self, text: str) -> None:
        self.logs.append(f"DETECTING:{text}")

    def current_save_dir(self) -> str:
        return "/tmp/save"


class _FakeWorkflow:
    def __init__(self) -> None:
        self.settings = AppSettings(
            download_dir_video="/v",
            download_dir_audio="/a",
            download_dir_subtitle="/s",
        )
        self.calls: list[dict] = []
        self.retry_calls: list[DownloadRequest] = []
        self.run_called = False

    def build_download_request(self, **kwargs):
        self.calls.append(kwargs)
        return DownloadRequest(
            kind=kwargs["kind"],
            url=kwargs["url"],
            dest_dir=kwargs["dest_dir"],
            format_id=kwargs.get("format_id", ""),
            audio_format_id=kwargs.get("audio_format_id", ""),
            subtitle_lang=kwargs.get("subtitle_lang", ""),
            transcode_to=kwargs.get("transcode_to", ""),
            cookies_from=kwargs.get("cookies_from"),
            extra_args=kwargs.get("extra_args", ()),
        )

    def retry_with_redetect(self, req: DownloadRequest, on_progress=None):
        self.retry_calls.append(req)
        if on_progress is not None:
            on_progress(ProgressEvent(stage="download", message="line1\rline2\n", percent=None))
        return TaskResult(ok=True, state="success", saved_path="/tmp/out.mp4")

    def run_download(self, req: DownloadRequest, on_progress=None):
        self.run_called = True
        return TaskResult(ok=False, state="error", error="should not be called")


def _make_controller(app_controller_cls, window: _FakeWindow, workflow: _FakeWorkflow):
    controller = object.__new__(app_controller_cls)
    controller._window = window
    controller._workflow = workflow
    controller._download_log_buffer = ""
    controller._active_thread = None
    return controller


def test_build_download_request_audio_uses_audio_dir(monkeypatch):
    controllers, _ = _load_gui_modules(monkeypatch)
    window = _FakeWindow()
    workflow = _FakeWorkflow()
    controller = _make_controller(controllers.AppController, window, workflow)

    req = controller._build_download_request(kind="audio", url="http://x.com")

    assert req is not None
    assert req.kind == "audio"
    assert req.dest_dir == "/a"
    assert req.format_id == "140"
    assert req.transcode_to == "mp3"
    assert req.extra_args == (
        "--download-sections",
        "*00:00:10-00:00:20",
        "--sponsorblock-remove",
        "sponsor,selfpromo",
        "--no-playlist",
    )


def test_build_download_request_subtitle_uses_subtitle_dir(monkeypatch):
    controllers, _ = _load_gui_modules(monkeypatch)
    window = _FakeWindow()
    workflow = _FakeWorkflow()
    controller = _make_controller(controllers.AppController, window, workflow)

    req = controller._build_download_request(kind="subtitle", url="http://x.com")

    assert req is not None
    assert req.kind == "subtitle"
    assert req.dest_dir == "/s"
    assert req.subtitle_lang == "auto:en"
    # 字幕走保守策略：不拼结构化媒体参数，仅透传手动参数
    assert req.extra_args == ("--no-playlist",)


def test_build_download_request_playlist_uses_mode(monkeypatch):
    controllers, _ = _load_gui_modules(monkeypatch)
    window = _FakeWindow()
    workflow = _FakeWorkflow()
    controller = _make_controller(controllers.AppController, window, workflow)

    req = controller._build_download_request(kind="playlist", url="http://x.com/list")

    assert req is not None
    assert req.kind == "playlist"
    assert req.dest_dir == "/v"
    assert req.format_id == "audio"
    assert "--sponsorblock-remove" in req.extra_args


def test_sponsorblock_defaults_to_config_categories_when_empty(monkeypatch):
    controllers, _ = _load_gui_modules(monkeypatch)
    window = _FakeWindow()
    workflow = _FakeWorkflow()
    window.sponsorblock_categories = ""
    controller = _make_controller(controllers.AppController, window, workflow)

    req = controller._build_download_request(kind="video", url="http://x.com/v")

    assert req is not None
    assert "--sponsorblock-remove" in req.extra_args
    idx = req.extra_args.index("--sponsorblock-remove")
    assert req.extra_args[idx + 1] == ",".join(config.YT_SPONSORBLOCK_DEFAULT_CATEGORIES)


def test_build_download_request_video_missing_selection_reports_error(monkeypatch):
    controllers, _ = _load_gui_modules(monkeypatch)
    window = _FakeWindow()
    workflow = _FakeWorkflow()
    window.video_id = ""
    controller = _make_controller(controllers.AppController, window, workflow)

    req = controller._build_download_request(kind="video", url="http://x.com")

    assert req is None
    assert any("选择视频格式" in msg for msg in window.errors)


def test_download_progress_flushes_by_newline(monkeypatch):
    controllers, _ = _load_gui_modules(monkeypatch)
    window = _FakeWindow()
    workflow = _FakeWorkflow()
    controller = _make_controller(controllers.AppController, window, workflow)

    controller._on_download_progress(
        ProgressEvent(stage="download", message="a\rb\nc", percent=None),
    )

    assert "a" in window.logs
    assert "b" in window.logs
    assert controller._download_log_buffer == "c"


def test_download_worker_uses_retry_with_redetect(monkeypatch):
    _, workers = _load_gui_modules(monkeypatch)
    workflow = _FakeWorkflow()
    req = DownloadRequest(kind="video", url="http://x.com", dest_dir="/tmp", format_id="137")
    worker = workers.DownloadWorker(workflow, req)

    worker.run()

    assert len(workflow.retry_calls) == 1
    assert workflow.retry_calls[0].kind == "video"
    assert workflow.run_called is False
