"""最小 GUI 主窗口。"""
from __future__ import annotations

import shlex

from PySide6.QtCore import Qt
from PySide6.QtWidgets import (
    QComboBox,
    QFileDialog,
    QFormLayout,
    QGroupBox,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMainWindow,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QSizePolicy,
    QTreeWidget,
    QTreeWidgetItem,
    QVBoxLayout,
    QWidget,
)

from ..core import config
from ..services.models import DetectResponse


# ── 辅助函数 ──────────────────────────────────────────────────────────────────

def _fmt_size(bytes_val: int) -> str:
    """将字节数格式化为人类可读的文件大小字符串。"""
    if not bytes_val:
        return "—"
    if bytes_val < 1024 * 1024:
        return f"{bytes_val / 1024:.0f} KB"
    if bytes_val < 1024 * 1024 * 1024:
        return f"{bytes_val / (1024 * 1024):.1f} MB"
    return f"{bytes_val / (1024 * 1024 * 1024):.2f} GB"


def _short_codec(codec: str) -> str:
    """将 yt-dlp 的完整编码字符串缩短为常见名称。"""
    c = codec.lower()
    if c.startswith("avc1") or c.startswith("h264"):
        return "H.264"
    if c.startswith("hev1") or c.startswith("h265") or c.startswith("hevc"):
        return "H.265"
    if c.startswith("vp09") or c.startswith("vp9"):
        return "VP9"
    if c.startswith("av01"):
        return "AV1"
    if c.startswith("mp4a"):
        return "AAC"
    if c == "opus":
        return "Opus"
    if c == "vorbis":
        return "Vorbis"
    if c == "mp3":
        return "MP3"
    if c == "none":
        return "—"
    return codec[:10]


class MainWindow(QMainWindow):
    """主窗口：环境检查、格式探测与多类型下载。"""

    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("yt-tool")
        self.setMinimumSize(880, 700)
        self.resize(1020, 860)

        root = QWidget(self)
        self.setCentralWidget(root)
        layout = QVBoxLayout(root)
        layout.setSpacing(8)

        # ── 输入区 ────────────────────────────────────────────────────────────
        top_box = QGroupBox("输入")
        top_layout = QFormLayout(top_box)
        top_layout.setFieldGrowthPolicy(
            QFormLayout.FieldGrowthPolicy.ExpandingFieldsGrow
        )
        top_layout.setLabelAlignment(Qt.AlignmentFlag.AlignRight)
        top_layout.setHorizontalSpacing(10)
        top_layout.setVerticalSpacing(6)

        self.url_input = QLineEdit()
        self.url_input.setPlaceholderText("https://www.youtube.com/watch?v=...")
        top_layout.addRow("URL", self.url_input)

        self.cookies_input = QLineEdit()
        self.cookies_input.setPlaceholderText("chrome / firefox（可选，留空则不使用）")
        top_layout.addRow("Cookies", self.cookies_input)

        self.kind_combo = QComboBox()
        self.kind_combo.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        self.kind_combo.addItem("视频", userData="video")
        self.kind_combo.addItem("音频", userData="audio")
        self.kind_combo.addItem("字幕", userData="subtitle")
        self.kind_combo.addItem("播放列表", userData="playlist")
        top_layout.addRow("下载类型", self.kind_combo)

        # 保存路径 — 可编辑，附带浏览按钮
        save_row = QHBoxLayout()
        self.save_dir_input = QLineEdit()
        self.save_dir_input.setReadOnly(True)
        self._browse_btn = QPushButton("浏览…")
        self._browse_btn.setFixedWidth(72)
        self._browse_btn.clicked.connect(self._on_browse_save_dir)
        save_row.addWidget(self.save_dir_input)
        save_row.addWidget(self._browse_btn)
        top_layout.addRow("保存到", save_row)

        self.transcode_input = QLineEdit()
        self.transcode_input.setPlaceholderText("mp3 / m4a（音频转码，可选）")
        top_layout.addRow("音频转码", self.transcode_input)

        self.playlist_mode_combo = QComboBox()
        self.playlist_mode_combo.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        self.playlist_mode_combo.addItem("视频", userData="video")
        self.playlist_mode_combo.addItem("音频", userData="audio")
        top_layout.addRow("播放列表模式", self.playlist_mode_combo)

        self.download_sections_input = QLineEdit()
        self.download_sections_input.setPlaceholderText("*00:00:30-00:01:30（可选）")
        top_layout.addRow("下载片段", self.download_sections_input)

        self.sponsorblock_mode_combo = QComboBox()
        self.sponsorblock_mode_combo.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        self.sponsorblock_mode_combo.addItem("不使用", userData="")
        self.sponsorblock_mode_combo.addItem("标记", userData="mark")
        self.sponsorblock_mode_combo.addItem("移除", userData="remove")
        top_layout.addRow("SponsorBlock", self.sponsorblock_mode_combo)

        self.sponsorblock_categories_input = QLineEdit()
        self.sponsorblock_categories_input.setPlaceholderText(
            ",".join(config.YT_SPONSORBLOCK_DEFAULT_CATEGORIES)
        )
        top_layout.addRow("SB 分类", self.sponsorblock_categories_input)

        self.extra_args_input = QLineEdit()
        self.extra_args_input.setPlaceholderText("--no-playlist")
        top_layout.addRow("额外参数", self.extra_args_input)

        btn_row = QHBoxLayout()
        self.env_button = QPushButton("环境检查")
        self.detect_button = QPushButton("探测格式")
        self.download_button = QPushButton("开始下载")
        btn_row.addWidget(self.env_button)
        btn_row.addWidget(self.detect_button)
        btn_row.addWidget(self.download_button)
        top_layout.addRow(btn_row)

        # ── 状态区 ────────────────────────────────────────────────────────────
        status_box = QGroupBox("状态")
        status_layout = QHBoxLayout(status_box)
        status_layout.setSpacing(20)
        self.env_label = QLabel("未检查")
        self.detect_summary = QLabel("未探测")
        status_layout.addWidget(self.env_label)
        status_layout.addWidget(self.detect_summary)
        status_layout.addStretch()

        # ── 探测结果（三列横排，视频/音频用 QTreeWidget 带列头） ───────────────
        result_box = QGroupBox("探测结果")
        result_layout = QHBoxLayout(result_box)
        result_layout.setSpacing(10)

        # 视频流
        video_col = QVBoxLayout()
        video_col.setSpacing(4)
        video_col.addWidget(QLabel("视频流"))
        self.video_list = QTreeWidget()
        self.video_list.setRootIsDecorated(False)
        self.video_list.setAlternatingRowColors(True)
        self.video_list.setColumnCount(8)
        self.video_list.setHeaderLabels(
            ["格式ID", "分辨率", "FPS", "总码率", "编码", "格式", "大小", "注"]
        )
        self.video_list.header().setSectionResizeMode(QHeaderView.ResizeMode.ResizeToContents)
        self.video_list.header().setStretchLastSection(True)
        self.video_list.setMinimumHeight(130)
        video_col.addWidget(self.video_list)
        result_layout.addLayout(video_col, stretch=2)

        # 音频流
        audio_col = QVBoxLayout()
        audio_col.setSpacing(4)
        audio_col.addWidget(QLabel("音频流"))
        self.audio_list = QTreeWidget()
        self.audio_list.setRootIsDecorated(False)
        self.audio_list.setAlternatingRowColors(True)
        self.audio_list.setColumnCount(6)
        self.audio_list.setHeaderLabels(["格式ID", "码率", "编码", "格式", "声道", "大小"])
        self.audio_list.header().setSectionResizeMode(QHeaderView.ResizeMode.ResizeToContents)
        self.audio_list.header().setStretchLastSection(True)
        self.audio_list.setMinimumHeight(130)
        audio_col.addWidget(self.audio_list)
        result_layout.addLayout(audio_col, stretch=1)

        # 字幕
        sub_col = QVBoxLayout()
        sub_col.setSpacing(4)
        sub_col.addWidget(QLabel("字幕"))
        self.subtitle_list = QListWidget()
        self.subtitle_list.setMinimumHeight(130)
        sub_col.addWidget(self.subtitle_list)
        result_layout.addLayout(sub_col, stretch=1)

        # ── 日志区 ────────────────────────────────────────────────────────────
        log_box = QGroupBox("日志")
        log_layout = QVBoxLayout(log_box)
        self.log_view = QPlainTextEdit()
        self.log_view.setReadOnly(True)
        self.log_view.setMaximumHeight(150)
        log_layout.addWidget(self.log_view)

        layout.addWidget(top_box)
        layout.addWidget(status_box)
        layout.addWidget(result_box, stretch=1)
        layout.addWidget(log_box)

        # 初始化保存路径默认值
        self._update_save_dir_default("video")
        self.kind_combo.currentIndexChanged.connect(self._on_kind_changed)

    # ── 内部槽 ────────────────────────────────────────────────────────────────

    def _on_kind_changed(self, _index: int) -> None:
        kind = self.kind_combo.currentData()
        self._update_save_dir_default(str(kind) if kind is not None else "video")

    def _update_save_dir_default(self, kind: str) -> None:
        if kind == "audio":
            default = str(config.YT_DIR_AUDIO)
        elif kind == "subtitle":
            default = str(config.YT_DIR_SUBTITLE)
        else:
            default = str(config.YT_DIR_VIDEO)
        # Only update placeholder; don't overwrite a path the user manually typed.
        self.save_dir_input.setPlaceholderText(default)

    def _on_browse_save_dir(self) -> None:
        current = self.save_dir_input.text().strip() or self.save_dir_input.placeholderText()
        path = QFileDialog.getExistingDirectory(
            self,
            "选择保存位置",
            current,
            QFileDialog.Option.ShowDirsOnly,
        )
        if path:
            self.save_dir_input.setText(path)

    # ── 公开接口 ──────────────────────────────────────────────────────────────

    def current_save_dir(self) -> str:
        """返回用户选定的保存目录；未填写时返回当前类型的配置默认目录。"""
        return self.save_dir_input.text().strip() or self.save_dir_input.placeholderText()

    def set_busy(self, busy: bool) -> None:
        self.env_button.setEnabled(not busy)
        self.detect_button.setEnabled(not busy)
        self.download_button.setEnabled(not busy)
        self._browse_btn.setEnabled(not busy)
        self.kind_combo.setEnabled(not busy)
        self.transcode_input.setEnabled(not busy)
        self.playlist_mode_combo.setEnabled(not busy)
        self.download_sections_input.setEnabled(not busy)
        self.sponsorblock_mode_combo.setEnabled(not busy)
        self.sponsorblock_categories_input.setEnabled(not busy)
        self.extra_args_input.setEnabled(not busy)

    def set_detecting_status(self, text: str) -> None:
        self.detect_summary.setText(text)

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
            missing_names = [item.name for item in result.items if not item.found and item.required]
            missing = ", ".join(missing_names) if missing_names else "未知"
            text = f"环境检查失败: 缺少 {missing}"
        self.env_label.setText(text)
        self.append_log(text)

    def set_detect_response(self, response: DetectResponse) -> None:
        self.clear_detect_result()

        for f in response.video_formats:
            item = QTreeWidgetItem([
                f.id,
                f"{f.height}p" if f.height else "—",
                f"{f.fps}" if f.fps else "—",
                f"{f.tbr:.0f} kbps" if f.tbr else "—",
                _short_codec(f.codec),
                f.ext,
                _fmt_size(f.filesize_approx),
                f.note,
            ])
            item.setData(0, Qt.ItemDataRole.UserRole, f.id)
            self.video_list.addTopLevelItem(item)

        for f in response.audio_formats:
            channels = f"{f.audio_channels}ch" if f.audio_channels else "—"
            item = QTreeWidgetItem([
                f.id,
                f"{f.abr:.0f} kbps" if f.abr else "—",
                _short_codec(f.codec),
                f.ext,
                channels,
                _fmt_size(f.filesize_approx),
            ])
            item.setData(0, Qt.ItemDataRole.UserRole, f.id)
            self.audio_list.addTopLevelItem(item)

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

        if self.video_list.topLevelItemCount() > 0:
            self.video_list.setCurrentItem(self.video_list.topLevelItem(0))
        if self.audio_list.topLevelItemCount() > 0:
            self.audio_list.setCurrentItem(self.audio_list.topLevelItem(0))
        if self.subtitle_list.count() > 0:
            self.subtitle_list.setCurrentRow(0)

    def show_error(self, message: str) -> None:
        QMessageBox.critical(self, "错误", message)
        self.append_log(f"ERROR: {message}")

    def show_result(self, path: str) -> None:
        message = f"下载完成: {path}" if path else "下载完成"
        QMessageBox.information(self, "完成", message)
        self.append_log(message)

    def selected_video_format_id(self) -> str:
        item = self.video_list.currentItem()
        if item is None:
            return ""
        value = item.data(0, Qt.ItemDataRole.UserRole)
        return str(value) if value is not None else ""

    def selected_audio_format_id(self) -> str:
        item = self.audio_list.currentItem()
        if item is None:
            return ""
        value = item.data(0, Qt.ItemDataRole.UserRole)
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

    def current_download_sections(self) -> str | None:
        value = self.download_sections_input.text().strip()
        return value or None

    def current_sponsorblock_mode(self) -> str | None:
        value = self.sponsorblock_mode_combo.currentData()
        if value is None:
            return None
        text = str(value).strip()
        return text or None

    def current_sponsorblock_categories(self) -> str | None:
        value = self.sponsorblock_categories_input.text().strip()
        return value or None

    def current_extra_args(self) -> tuple[str, ...]:
        raw = self.extra_args_input.text().strip()
        if not raw:
            return ()
        try:
            return tuple(shlex.split(raw))
        except ValueError:
            return (raw,)
