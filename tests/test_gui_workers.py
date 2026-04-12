"""Unit tests for app.gui.workers signal paths."""
from __future__ import annotations

import importlib
import sys
from types import ModuleType
from unittest.mock import MagicMock

import pytest

from app.services.models import DetectRequest, DownloadRequest, ProgressEvent, TaskResult


# ---------------------------------------------------------------------------
# Fake PySide6 (same pattern as test_gui_controller.py)
# ---------------------------------------------------------------------------

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

        def deleteLater(self):
            return None

    class _QThread(_QObject):
        def __init__(self, parent=None):
            super().__init__(parent)
            self.finished = _Signal()

        def start(self):
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


def _load_workers(monkeypatch):
    pyside6, qtcore = _make_fake_pyside6()
    monkeypatch.setitem(sys.modules, "PySide6", pyside6)
    monkeypatch.setitem(sys.modules, "PySide6.QtCore", qtcore)
    workers = importlib.import_module("app.gui.workers")
    importlib.reload(workers)
    return workers


# ---------------------------------------------------------------------------
# EnvCheckWorker
# ---------------------------------------------------------------------------

class TestEnvCheckWorker:
    def test_finished_emitted_on_success(self, monkeypatch):
        workers = _load_workers(monkeypatch)
        fake_result = object()
        workflow = MagicMock()
        workflow.check_environment.return_value = fake_result

        w = workers.EnvCheckWorker(workflow)
        captured = []
        w.task_finished.connect(captured.append)

        w.run()

        assert captured == [fake_result]
        workflow.check_environment.assert_called_once()

    def test_failed_not_emitted_on_success(self, monkeypatch):
        workers = _load_workers(monkeypatch)
        workflow = MagicMock()
        workflow.check_environment.return_value = object()

        w = workers.EnvCheckWorker(workflow)
        errors = []
        w.task_failed.connect(errors.append)

        w.run()

        assert errors == []


# ---------------------------------------------------------------------------
# DetectWorker
# ---------------------------------------------------------------------------

class TestDetectWorker:
    def _make_request(self):
        return DetectRequest(url="http://example.com/v")

    def test_finished_emitted_on_success(self, monkeypatch):
        workers = _load_workers(monkeypatch)
        fake_result = object()
        workflow = MagicMock()
        workflow.detect_formats.return_value = fake_result
        req = self._make_request()

        w = workers.DetectWorker(workflow, req)
        captured = []
        w.task_finished.connect(captured.append)

        w.run()

        assert captured == [fake_result]
        workflow.detect_formats.assert_called_once_with(req)

    def test_failed_emitted_on_exception(self, monkeypatch):
        workers = _load_workers(monkeypatch)
        workflow = MagicMock()
        workflow.detect_formats.side_effect = RuntimeError("network error")
        req = self._make_request()

        w = workers.DetectWorker(workflow, req)
        errors = []
        finished = []
        w.task_failed.connect(errors.append)
        w.task_finished.connect(finished.append)

        w.run()

        assert errors == ["network error"]
        assert finished == []


# ---------------------------------------------------------------------------
# DownloadWorker
# ---------------------------------------------------------------------------

class TestDownloadWorker:
    def _make_request(self):
        return DownloadRequest(
            kind="video",
            url="http://example.com/v",
            dest_dir="/tmp",
        )

    def test_finished_emitted_on_success(self, monkeypatch):
        workers = _load_workers(monkeypatch)
        fake_result = TaskResult(ok=True, state="success", saved_path="/tmp/video.mp4")
        workflow = MagicMock()
        workflow.retry_with_redetect.return_value = fake_result
        req = self._make_request()

        w = workers.DownloadWorker(workflow, req)
        captured = []
        w.task_finished.connect(captured.append)

        w.run()

        assert captured == [fake_result]
        call_kwargs = workflow.retry_with_redetect.call_args
        assert call_kwargs.args[0] is req
        assert "on_progress" in call_kwargs.kwargs

    def test_failed_emitted_on_exception(self, monkeypatch):
        workers = _load_workers(monkeypatch)
        workflow = MagicMock()
        workflow.retry_with_redetect.side_effect = ValueError("bad format")
        req = self._make_request()

        w = workers.DownloadWorker(workflow, req)
        errors = []
        finished = []
        w.task_failed.connect(errors.append)
        w.task_finished.connect(finished.append)

        w.run()

        assert errors == ["bad format"]
        assert finished == []

    def test_progress_callback_wired(self, monkeypatch):
        workers = _load_workers(monkeypatch)
        progress_events = []
        fake_result = TaskResult(ok=True, state="success", saved_path="/tmp/video.mp4")

        def fake_retry(request, *, on_progress):
            on_progress(ProgressEvent(stage="download", message="50%"))
            on_progress(ProgressEvent(stage="download", message="100%"))
            return fake_result

        workflow = MagicMock()
        workflow.retry_with_redetect.side_effect = fake_retry
        req = self._make_request()

        w = workers.DownloadWorker(workflow, req)
        w.progress.connect(progress_events.append)

        w.run()

        assert len(progress_events) == 2
        assert progress_events[0].message == "50%"
        assert progress_events[1].message == "100%"
