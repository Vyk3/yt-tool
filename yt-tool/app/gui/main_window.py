"""最小 GUI 主窗口。"""
from __future__ import annotations

import shlex

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QComboBox,
    QFormLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMainWindow,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from ..services.models import DetectResponse


class MainWindow(QMainWindow):
    """M2 最小 GUI：环境检查 + 格式探测。"""

    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("yt-tool GUI (M2)")
        self.resize(900, 640)

        root = QWidget(self)
        self.setCentralWidget(root)
        layout = QVBoxLayout(root)

        top_box = QGroupBox("输入")
        top_layout = QFormLayout(top_box)
        self.url_input = QLineEdit()
        self.url_input.setPlaceholderText("https://www.youtube.com/watch?v=...")
        top_layout.addRow("URL", self.url_input)

        self.cookies_input = QLineEdit()
        self.cookies_input.setPlaceholderText("chrome / firefox (optional)")
        top_layout.addRow("Cookies", self.cookies_input)

        self.kind_combo = QComboBox()
        self.kind_combo.addItem("视频", userData="video")
        self.kind_combo.addItem("音频", userData="audio")
        self.kind_combo.addItem("字幕", userData="subtitle")
        self.kind_combo.addItem("播放列表", userData="playlist")
        top_layout.addRow("下载类型", self.kind_combo)

        self.transcode_input = QLineEdit()
        self.transcode_input.setPlaceholderText("mp3 / m4a (audio optional)")
        top_layout.addRow("音频转码", self.transcode_input)

        self.playlist_mode_combo = QComboBox()
        self.playlist_mode_combo.addItem("视频", userData="video")
        self.playlist_mode_combo.addItem("音频", userData="audio")
        top_layout.addRow("播放列表模式", self.playlist_mode_combo)

        self.extra_args_input = QLineEdit()
        self.extra_args_input.setPlaceholderText("--sponsorblock-remove all")
        top_layout.addRow("额外参数", self.extra_args_input)

        button_row = QHBoxLayout()
        self.env_button = QPushButton("环境检查")
        self.detect_button = QPushButton("探测格式")
        self.download_button = QPushButton("开始下载")
        button_row.addWidget(self.env_button)
        button_row.addWidget(self.detect_button)
        button_row.addWidget(self.download_button)
        top_layout.addRow(button_row)

        status_box = QGroupBox("状态")
        status_layout = QVBoxLayout(status_box)
        self.env_label = QLabel("未检查")
        self.detect_summary = QLabel("未探测")
        status_layout.addWidget(self.env_label)
        status_layout.addWidget(self.detect_summary)

        result_box = QGroupBox("探测结果")
        result_layout = QVBoxLayout(result_box)
        self.video_list = QListWidget()
        self.audio_list = QListWidget()
        self.subtitle_list = QListWidget()
        result_layout.addWidget(QLabel("视频流"))
        result_layout.addWidget(self.video_list)
        result_layout.addWidget(QLabel("音频流"))
        result_layout.addWidget(self.audio_list)
        result_layout.addWidget(QLabel("字幕"))
        result_layout.addWidget(self.subtitle_list)

        log_box = QGroupBox("日志")
        log_layout = QVBoxLayout(log_box)
        self.log_view = QPlainTextEdit()
        self.log_view.setReadOnly(True)
        log_layout.addWidget(self.log_view)

        layout.addWidget(top_box)
        layout.addWidget(status_box)
        layout.addWidget(result_box)
        layout.addWidget(log_box)

    def set_busy(self, busy: bool) -> None:
        self.env_button.setEnabled(not busy)
        self.detect_button.setEnabled(not busy)
        self.download_button.setEnabled(not busy)
        self.kind_combo.setEnabled(not busy)
        self.transcode_input.setEnabled(not busy)
        self.playlist_mode_combo.setEnabled(not busy)
        self.extra_args_input.setEnabled(not busy)

    def current_url(self) -> str:
        return self.url_input.text().strip()

    def current_cookies_from(self) -> str | None:
        value = self.cookies_input.text().strip()
        return value or None

    def append_log(self, message: str) -> None:
        if message.strip():
            self.log_view.appendPlainText(message.rstrip("\n"))

    def clear_detect_result(self) -> None:
        self.video_list.clear()
        self.audio_list.clear()
        self.subtitle_list.clear()

    def set_env_check_result(self, result: object) -> None:
        if result.ok:
            text = "环境检查通过"
        else:
            missing = ", ".join(result.missing) if result.missing else "未知"
            text = f"环境检查失败: 缺少 {missing}"
        self.env_label.setText(text)
        self.append_log(text)

    def set_detect_response(self, response: DetectResponse) -> None:
        self.clear_detect_result()
        for f in response.video_formats:
            item = QListWidgetItem(f"{f.id}  {f.height}p  {f.codec}  {f.ext}")
            item.setData(Qt.ItemDataRole.UserRole, f.id)
            self.video_list.addItem(item)
        for f in response.audio_formats:
            item = QListWidgetItem(f"{f.id}  {f.abr:.0f}kbps  {f.codec}  {f.ext}")
            item.setData(Qt.ItemDataRole.UserRole, f.id)
            self.audio_list.addItem(item)
        for t in response.subtitles:
            item = QListWidgetItem(f"{t.lang}  {t.label}")
            item.setData(Qt.ItemDataRole.UserRole, t.lang)
            self.subtitle_list.addItem(item)
        for t in response.auto_subtitles:
            item = QListWidgetItem(f"auto:{t.lang}  {t.label}")
            item.setData(Qt.ItemDataRole.UserRole, f"auto:{t.lang}")
            self.subtitle_list.addItem(item)
        self.detect_summary.setText("探测完成")
        self.append_log("探测完成")
        if self.video_list.count() > 0:
            self.video_list.setCurrentRow(0)
        if self.audio_list.count() > 0:
            self.audio_list.setCurrentRow(0)
        if self.subtitle_list.count() > 0:
            self.subtitle_list.setCurrentRow(0)

    def show_error(self, message: str) -> None:
        QMessageBox.critical(self, "Error", message)
        self.append_log(f"ERROR: {message}")

    def show_result(self, path: str) -> None:
        message = f"下载完成: {path}" if path else "下载完成"
        QMessageBox.information(self, "Done", message)
        self.append_log(message)

    def selected_video_format_id(self) -> str:
        item = self.video_list.currentItem()
        if item is None:
            return ""
        value = item.data(Qt.ItemDataRole.UserRole)
        return str(value) if value is not None else ""

    def selected_audio_format_id(self) -> str:
        item = self.audio_list.currentItem()
        if item is None:
            return ""
        value = item.data(Qt.ItemDataRole.UserRole)
        return str(value) if value is not None else ""

    def selected_subtitle_lang(self) -> str:
        item = self.subtitle_list.currentItem()
        if item is None:
            return ""
        value = item.data(Qt.ItemDataRole.UserRole)
        return str(value) if value is not None else ""

    def current_download_kind(self) -> str:
        value = self.kind_combo.currentData()
        return str(value) if value is not None else "video"

    def current_playlist_mode(self) -> str:
        value = self.playlist_mode_combo.currentData()
        return str(value) if value is not None else "video"

    def current_transcode_to(self) -> str:
        return self.transcode_input.text().strip()

    def current_extra_args(self) -> tuple[str, ...]:
        raw = self.extra_args_input.text().strip()
        if not raw:
            return ()
        try:
            return tuple(shlex.split(raw))
        except ValueError:
            return (raw,)
