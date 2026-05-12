# Changelog

## [0.1.2] — 2026-05-12

### Changed
- yt-dlp 运行时从 PyInstaller 独立二进制切换为 Python zipapp + 嵌入式 Python 3.12 运行时
  - 启动时间：12.9s → 0.5s；yt-dlp 体积：35MB → 3MB
- ffmpeg / ffprobe 升级至 8.1，切换为 arm64 原生构建（OSXExperts.NET）
- 发布产物统一为 arm64 架构，.zip 从 97MB 降至 74MB，.dmg 从 82MB 降至 70MB

### Removed
- 移除发布产物中的 x86_64（Intel）ffmpeg / ffprobe 构建路径
- 官方打包发布版不再提供 Intel Mac build

### Notes
- 官方打包发布版（YTTool.dmg / YTTool.zip）仅支持 Apple Silicon（M1 或更新）
- Intel Mac 不属于当前发布产物支持范围

---

## [0.1.1] — 2026-05-08

### Added
- **aria2c 集成**：支持通过 PATH 检测的 aria2c 实现多连接加速下载（`--downloader aria2c -x 16 -s 16`），不可用时自动回退内置下载器。Advanced Options 中可切换。
- **下载队列**：支持多 URL 批量入队、顺序下载。入队时快照当前配置，队列项互不影响。支持拖拽重排序、取消、重试、清除已完成项。
- **yt-dlp 自更新**：Settings 中可检查并安装 yt-dlp 新版本（Stable / Nightly 频道），无需等待 app 更新。更新后的二进制存放于 `~/Library/Application Support/YTTool/Binaries/`，优先于 bundled 版本加载。启动时自动验证用户本地二进制完整性。

---

## [0.1.0] — 2026-05-06

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
