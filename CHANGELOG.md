# Changelog

## Unreleased

### Changed
- **平台切换**：从 Python（PyInstaller + pywebview）全面迁移到 Swift 原生 macOS App（SwiftUI）。
- **CI 更新**：CI workflow 从 Python pytest/ruff 替换为 Swift 测试（`swift test`）和构建检查（`xcodebuild build`）。
- **Release 更新**：Release workflow 从 PyInstaller 打包切换为 `scripts/build/swift/build.sh --release`，产物为 `YTTool.zip`。
- 清理 Python 应用代码（`app/`、`tests/`）、Windows 构建脚本、Python launcher 及相关依赖。

### Added
Swift 重写完整功能覆盖，包括：
- 视频 / 音频下载，含格式选择与磁盘空间预检
- 音频转码格式选择（`mp3 / m4a / wav`，含 `Keep original`）
- Cookies 文件路径传透（probe / download 均支持）
- 额外 yt-dlp 参数透传（含引号参数解析）
- 播放列表模式（`Only first item` / `Whole playlist: best video` / `Whole playlist: best audio`）
- 整列表字幕策略（manual / auto + lang）
- 整列表片段策略（`Fixed time range` → `--download-sections`）
- 整列表逐条格式映射（`Per-item mapping`）
- 下载完成系统通知、会话 Session Log、URL 拖拽输入
- ffmpeg / ffprobe 缺失时的 `FFmpeg unavailable` 明确提示
