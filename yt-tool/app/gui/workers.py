"""GUI 后台 worker。"""
from __future__ import annotations

from PySide6.QtCore import QObject, Signal, Slot

from ..services.models import DetectRequest, DownloadRequest
from ..services.workflow import AppWorkflow


class EnvCheckWorker(QObject):
    """后台执行环境检查。"""

    finished = Signal(object)
    failed = Signal(str)

    def __init__(self, workflow: AppWorkflow) -> None:
        super().__init__()
        self._workflow = workflow

    @Slot()
    def run(self) -> None:
        try:
            result = self._workflow.check_environment()
        except Exception as exc:  # pragma: no cover - defensive branch
            self.failed.emit(str(exc))
            return
        self.finished.emit(result)


class DetectWorker(QObject):
    """后台执行格式探测。"""

    finished = Signal(object)
    failed = Signal(str)

    def __init__(self, workflow: AppWorkflow, request: DetectRequest) -> None:
        super().__init__()
        self._workflow = workflow
        self._request = request

    @Slot()
    def run(self) -> None:
        try:
            result = self._workflow.detect_formats(self._request)
        except Exception as exc:
            self.failed.emit(str(exc))
            return
        self.finished.emit(result)


class DownloadWorker(QObject):
    """后台执行下载任务（带格式失效重探测重试）。"""

    finished = Signal(object)
    failed = Signal(str)
    progress = Signal(object)

    def __init__(self, workflow: AppWorkflow, request: DownloadRequest) -> None:
        super().__init__()
        self._workflow = workflow
        self._request = request

    @Slot()
    def run(self) -> None:
        try:
            result = self._workflow.retry_with_redetect(
                self._request,
                on_progress=self.progress.emit,
            )
        except Exception as exc:
            self.failed.emit(str(exc))
            return
        self.finished.emit(result)
