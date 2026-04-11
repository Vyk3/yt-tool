"""GUI 控制器。"""
from __future__ import annotations

from typing import Literal
from typing import TYPE_CHECKING

from PySide6.QtCore import QObject, QThread

from ..core import config
from ..services.models import DetectRequest, ProgressEvent
from ..services.workflow import AppWorkflow
from .workers import DetectWorker, DownloadWorker, EnvCheckWorker

if TYPE_CHECKING:
    from .main_window import MainWindow


class AppController(QObject):
    """连接窗口事件与工作流调用。"""

    def __init__(self, window: MainWindow, workflow: AppWorkflow | None = None) -> None:
        super().__init__(window)
        self._window = window
        self._workflow = workflow or AppWorkflow()
        self._active_thread: QThread | None = None
        self._download_log_buffer = ""

        self._window.env_button.clicked.connect(self.run_env_check)
        self._window.detect_button.clicked.connect(self.detect_formats)
        self._window.download_button.clicked.connect(self.start_download)

    def startup(self) -> None:
        self._window.append_log("启动：开始环境检查")
        self.run_env_check()

    def run_env_check(self) -> None:
        worker = EnvCheckWorker(self._workflow)
        self._run_worker(
            worker,
            task_name="env",
            on_finished=self._on_env_finished,
            on_failed=self._on_worker_failed,
        )

    def detect_formats(self) -> None:
        url = self._window.current_url()
        if not url:
            self._window.show_error("URL 不能为空")
            return

        self._window.append_log("开始探测格式...")
        req = DetectRequest(
            url=url,
            cookies_from=self._window.current_cookies_from(),
        )
        worker = DetectWorker(self._workflow, req)
        self._run_worker(
            worker,
            task_name="detect",
            on_finished=self._on_detect_finished,
            on_failed=self._on_worker_failed,
        )

    def start_download(self) -> None:
        url = self._window.current_url()
        if not url:
            self._window.show_error("URL 不能为空")
            return

        kind = self._window.current_download_kind()
        request = self._build_download_request(kind=kind, url=url)
        if request is None:
            return

        self._download_log_buffer = ""
        worker = DownloadWorker(self._workflow, request)
        self._run_worker(
            worker,
            task_name="download",
            on_finished=self._on_download_finished,
            on_failed=self._on_worker_failed,
            on_progress=self._on_download_progress,
        )

    def _build_download_request(self, *, kind: str, url: str):
        cookies = self._window.current_cookies_from()
        extra_args = self._compose_extra_args(kind)

        if kind == "video":
            video_fmt = self._window.selected_video_format_id()
            if not video_fmt:
                self._window.show_error("请先探测并选择视频格式")
                return None
            return self._workflow.build_download_request(
                kind="video",
                url=url,
                dest_dir=self._workflow.settings.download_dir_video,
                format_id=video_fmt,
                audio_format_id=self._window.selected_audio_format_id(),
                cookies_from=cookies,
                extra_args=extra_args,
            )

        if kind == "audio":
            audio_fmt = self._window.selected_audio_format_id()
            if not audio_fmt:
                self._window.show_error("请先探测并选择音频格式")
                return None
            return self._workflow.build_download_request(
                kind="audio",
                url=url,
                dest_dir=self._workflow.settings.download_dir_audio,
                format_id=audio_fmt,
                transcode_to=self._window.current_transcode_to(),
                cookies_from=cookies,
                extra_args=extra_args,
            )

        if kind == "subtitle":
            subtitle_lang = self._window.selected_subtitle_lang()
            if not subtitle_lang:
                self._window.show_error("请先探测并选择字幕")
                return None
            return self._workflow.build_download_request(
                kind="subtitle",
                url=url,
                dest_dir=self._workflow.settings.download_dir_subtitle,
                subtitle_lang=subtitle_lang,
                cookies_from=cookies,
                extra_args=extra_args,
            )

        if kind == "playlist":
            return self._workflow.build_download_request(
                kind="playlist",
                url=url,
                dest_dir=self._workflow.settings.download_dir_video,
                format_id=self._window.current_playlist_mode(),
                cookies_from=cookies,
                extra_args=extra_args,
            )

        self._window.show_error(f"不支持的下载类型: {kind}")
        return None

    def _compose_extra_args(self, kind: str) -> tuple[str, ...]:
        args: list[str] = []

        if kind in ("video", "audio", "playlist"):
            download_sections = self._window.current_download_sections()
            if download_sections:
                args += ["--download-sections", download_sections]

            sponsorblock_mode = self._window.current_sponsorblock_mode()
            if sponsorblock_mode:
                categories = (
                    self._window.current_sponsorblock_categories()
                    or ",".join(config.YT_SPONSORBLOCK_DEFAULT_CATEGORIES)
                )
                flag = (
                    "--sponsorblock-mark"
                    if sponsorblock_mode == "mark"
                    else "--sponsorblock-remove"
                )
                args += [flag, categories]

        # 手动参数放在最后，便于用户按需覆盖结构化默认参数。
        args += list(self._window.current_extra_args())
        return tuple(args)

    def _run_worker(
        self,
        worker: QObject,
        *,
        task_name: Literal["env", "detect", "download"],
        on_finished,
        on_failed,
        on_progress=None,
    ) -> None:
        if self._active_thread is not None:
            self._window.append_log("上一个任务仍在进行，忽略本次请求")
            return

        thread = QThread(self)
        worker.moveToThread(thread)

        thread.started.connect(worker.run)
        worker.finished.connect(on_finished)
        worker.failed.connect(on_failed)
        if on_progress is not None and hasattr(worker, "progress"):
            worker.progress.connect(on_progress)
        worker.finished.connect(thread.quit)
        worker.failed.connect(thread.quit)
        thread.finished.connect(worker.deleteLater)
        thread.finished.connect(thread.deleteLater)
        thread.finished.connect(self._on_thread_finished)

        self._active_thread = thread
        self._window.set_busy(True)
        self._window.append_log(f"任务开始: {task_name}")
        thread.start()

    def _on_env_finished(self, result) -> None:
        self._window.set_env_check_result(result)

    def _on_detect_finished(self, result) -> None:
        self._window.set_detect_response(result)

    def _on_download_progress(self, event: ProgressEvent) -> None:
        text = event.message.replace("\r", "\n")
        self._download_log_buffer += text
        while "\n" in self._download_log_buffer:
            line, self._download_log_buffer = self._download_log_buffer.split("\n", 1)
            if line.strip():
                self._window.append_log(line)

    def _on_download_finished(self, result) -> None:
        if self._download_log_buffer.strip():
            self._window.append_log(self._download_log_buffer.strip())
        self._download_log_buffer = ""
        if result.ok:
            self._window.show_result(result.saved_path)
            return
        self._window.show_error(result.error or "下载失败")

    def _on_worker_failed(self, message: str) -> None:
        self._download_log_buffer = ""
        self._window.show_error(message)

    def _on_thread_finished(self) -> None:
        self._active_thread = None
        self._window.set_busy(False)
        self._window.append_log("任务结束")
