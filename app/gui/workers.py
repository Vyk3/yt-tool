"""GUI 后台 worker。"""
from __future__ import annotations

from PySide6.QtCore import QThread, Signal

from ..services.models import DetectRequest, DownloadRequest
from ..services.workflow import AppWorkflow


class EnvCheckWorker(QThread):
    """后台执行环境检查。"""

    task_finished = Signal(object)
    task_failed = Signal(str)

    def __init__(self, workflow: AppWorkflow) -> None:
        super().__init__()
        self._workflow = workflow

    def run(self) -> None:
        try:
            result = self._workflow.check_environment()
        except Exception as exc:  # pragma: no cover - defensive branch
            self.task_failed.emit(str(exc))
            return
        self.task_finished.emit(result)


class DetectWorker(QThread):
    """后台执行格式探测。"""

    task_finished = Signal(object)
    task_failed = Signal(str)

    def __init__(self, workflow: AppWorkflow, request: DetectRequest) -> None:
        super().__init__()
        self._workflow = workflow
        self._request = request

    def run(self) -> None:
        try:
            result = self._workflow.detect_formats(self._request)
        except Exception as exc:
            self.task_failed.emit(str(exc))
            return
        self.task_finished.emit(result)


class DownloadWorker(QThread):
    """后台执行下载任务（带格式失效重探测重试）。"""

    task_finished = Signal(object)
    task_failed = Signal(str)
    progress = Signal(object)

    def __init__(self, workflow: AppWorkflow, request: DownloadRequest) -> None:
        super().__init__()
        self._workflow = workflow
        self._request = request

    def run(self) -> None:
        try:
            result = self._workflow.retry_with_redetect(
                self._request,
                on_progress=self.progress.emit,
            )
        except Exception as exc:
            self.task_failed.emit(str(exc))
            return
        self.task_finished.emit(result)
