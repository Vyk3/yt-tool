# Changelog

本文档遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 格式，版本号遵循 [Semantic Versioning](https://semver.org/)。

---

## [Unreleased]

---

## [0.1.5] — 2026-05-30

### Added
- **频道订阅监控**：通过 URL 或 Channel ID 订阅 YouTube 频道，定时轮询 RSS feed 检测新视频并发送 macOS 通知。(#65)
- **统一 Settings 标签页**：新增 `SettingsTabView` 作为设置 UI 唯一入口，Settings 窗口和应用内 Settings 模式共用同一组件，消除原 `SettingsView` 中 About/Updates 的重复代码。(#65)
- **订阅相关单元测试**：新增 `FeedXMLParserTests`（9 项）和 `ChannelSubscriptionStoreTests`（13 项），覆盖 XML 解析、CRUD、持久化往返和异常文件处理。(#65)

### Changed
- `SubscriptionPollingManager` 使用 `TaskGroup` 并发拉取所有已订阅频道的 RSS feed，替代逐个串行请求。(#65)
  > Why：串行轮询在频道数量增多时延迟线性增长
- `ChannelSubscriptionStore` 新增 `performBatchUpdate` 批量写入模式，多频道更新时合并为单次磁盘写入。(#65)
  > Why：每次 `updateLastChecked` / `updateChannelName` 都触发一次写盘，N 个频道产生 2N 次 I/O
- `YouTubeFeedService.resolveChannelID` 使用 `withCheckedThrowingContinuation` + `terminationHandler` 替代阻塞式 `waitUntilExit()`。(#65)
  > Why：`waitUntilExit()` 阻塞 Swift 协作线程池，且 stdout pipe 超过 ~64KB 时导致死锁
- `AdvancedOptionsView` 显示当前引擎、Cookies 和额外参数状态摘要，引导用户在 Settings 标签页修改。(#65)
- 轮询间隔持久化到 UserDefaults，应用重启后保留用户选择的检查频率。(#65)

### Fixed
- 修复 `SubscriptionsView` 中 `URL(string:)!` 强制解包导致无效 URL 时的崩溃。(#65)
- 修复 `SubscriptionPollingManager` timer 未在 `deinit` 中 invalidate 导致的泄漏。(#65)
- 修复 Swift 6 strict concurrency 下 `@MainActor` 类的 `nonisolated deinit` 访问 timer 属性的编译错误。(#65)

---

## [0.1.4] — 2026-05-29

### Added
- **失败 / 取消状态操作按钮**：下载失败和取消面板新增 Retry（保留已选格式重试）与 New Download（完全重置）两个按钮。(#62)
- **队列播放列表支持**：自动识别 YouTube 纯播放列表 URL（`/playlist?list=`），跳过 `--no-playlist` 以下载整个列表；Watch URL 带 `list=` 参数不受影响。(#62)

### Changed
- `resetDownload()` 升级为完整重置：清除 URL、probe 状态、已选格式和下载状态，与 `retryDownload()`（仅重置下载状态）明确分工。(#62)
  > Why：原 `resetDownload` 仅重置下载状态，用户需要手动清空 URL 才能开始全新下载
- 提取 `recordDownloadResult()` 统一下载完成路径，合并单次下载和队列下载中 5 处重复的历史记录 + 通知逻辑。(#62)
  > Why：重复代码导致修改一处容易遗漏其余路径
- `DownloadQueue` 回调从 Optional 改为非 Optional（默认空闭包），`retryItem` 通过内部 `resumeProcessing()` 恢复处理循环，不覆盖已注册的回调。(#62)
  > Why：原实现中 `retryItem` 调用 `startProcessing` 会覆盖回调为 no-op，导致重试后的完成事件丢失

### Fixed
- 修复 `extract_release_notes.py` 提取最后一个版本时 off-by-one 导致内容截断的问题。(#62)
  > Why：当目标版本是 CHANGELOG 中最后一个版本时，循环结束未设置 `end`，导致 `section` 为空

---

## [0.1.3] — 2026-05-28

### Added
- **应用自更新**：集成 Sparkle 2.x，Ed25519 签名，appcast.xml 托管于 GitHub Pages。Settings 中可独立控制 app 更新检查开关。(#57)
- **下载历史**：持久化记录所有下载，支持 History Sheet 查看和搜索。(#55)
- **批量 URL 导入**：队列模式下支持从文件（.txt）或剪贴板批量导入 URL，自动过滤非 URL 行并去重。(#56)
- **预估合并大小**：格式选择后显示视频 + 音频合并后的预估文件大小。(#54)
- **文档一致性检查**：新增 `check_docs_coherence.py` 脚本，自动验证 markdown 链接、脚本路径和 CHANGELOG 覆盖度。(#58)

### Changed
- CI 加固：增加 `SWIFT_TREAT_WARNINGS_AS_ERRORS` 编译检查。(#56)
- 将 8 个播放列表相关 `@Published` 属性合并为 `PlaylistConfig` 值类型，URLInputView 参数从 14 个降至 6 个。(#59)
  > Why：减少跨 View 的 Binding 数量，降低参数传递出错概率
- 提取 `buildFormatSelector()` 共享函数，消除 AppState 与 YtDlpDownloadService 之间的格式选择器重复逻辑。(#59)
- `LockedTextBuffer` 增加 8 MB 容量上限与最旧块淘汰机制，防止长时间下载导致内存无限增长。(#59)
  > Why：长播放列表下载会持续追加输出，无上限时可耗尽内存
- 提取 `ServiceLogKind.appLogLevel` 计算属性和 `SelectableRowStyle` ViewModifier，消除重复代码。(#59)
- DownloadQueue 缓存 aria2c 路径查找结果，避免逐队列项调用 `/usr/bin/which`。(#59)

### Fixed
- 修复 aria2c 运行时检测回归：移除过时的 `aria2cAvailable` 守卫，恢复每次下载时重新查找 aria2c 的行为，并用查找结果刷新 UI 状态。(#59)
  > Why：`aria2cAvailable` 仅在 `init` 时初始化一次，用户在 app 启动后安装 aria2c 将永远检测不到

---

## [0.1.2] — 2026-05-12

### Changed
- yt-dlp 运行时从 PyInstaller 独立二进制切换为 Python zipapp + 嵌入式 Python 3.12 运行时。(#49)
  > Why：PyInstaller 二进制启动需 12.9s，zipapp 仅需 0.5s；体积从 35MB 降至 3MB
- ffmpeg / ffprobe 升级至 8.1，切换为 arm64 原生构建（OSXExperts.NET）。(#49)
- 发布产物统一为 arm64 架构，.zip 从 97MB 降至 74MB，.dmg 从 82MB 降至 70MB。(#49)
- 输出文件名模板增加 `[%(resolution)s]` 后缀，防止同一视频不同格式下载时文件名冲突。(#49)
  > Why：旧模板 `%(title)s.%(ext)s` 会导致不同分辨率的下载被跳过

### Removed
- 移除发布产物中的 x86_64（Intel）ffmpeg / ffprobe 构建路径。(#49)

### Notes
- 官方打包发布版仅支持 Apple Silicon（M1 或更新），Intel Mac 用户可通过源码自行构建。

---

## [0.1.1] — 2026-05-08

### Added
- **aria2c 集成**：检测 PATH 中的 aria2c 实现多连接加速下载，不可用时自动回退内置下载器。Advanced Options 中可切换。(#45)
  > Why：YouTube 等站点的分段下载通过 aria2c 的多连接能力可显著提速
- **下载队列**：支持多 URL 批量入队、顺序下载，入队时快照当前配置。支持拖拽重排序、取消、重试。(#46)
- **yt-dlp 自更新**：Settings 中可检查并安装 yt-dlp 新版本（Stable / Nightly 频道），无需等待 app 更新。(#47)
  > Why：yt-dlp 更新频率远高于 app 本体，站点兼容性依赖及时更新
- **DMG 分发产物**：build.sh 新增 DMG 生成步骤（含 /Applications symlink 拖拽安装），release workflow 同时上传 ZIP 和 DMG。(#44)

---

## [0.1.0] — 2026-05-07

### Changed
- **平台切换**：从 Python（PyInstaller + pywebview）全面迁移到 Swift 原生 macOS App（SwiftUI）。(#34, #41)
  > Why：原生 App 启动速度、内存占用和 macOS 集成度均优于 Python + WebView 方案
- CI workflow 从 Python pytest/ruff 替换为 Swift `swift test` + `xcodebuild build`。(#41)
- Release workflow 从 PyInstaller 切换为 `scripts/build/swift/build.sh --release`，产物为 YTTool.zip。(#41)
- 清理全部 Python 应用代码（`app/`、`tests/`）及 Windows 构建脚本。(#41)

### Added
Swift 重写完整功能覆盖：(#34, #35, #36, #37)
- 视频 / 音频下载，含格式选择与磁盘空间预检
- 音频转码格式选择（mp3 / m4a / wav，含 Keep original）
- Cookies 文件路径透传（probe / download 均支持）
- 额外 yt-dlp 参数透传（含引号参数解析）
- 播放列表模式（Only first item / Whole playlist: best video / Whole playlist: best audio）
- YouTube 专项优化：`player_client=default` 绕过 JS runtime、并发分段下载、metadata embed (#35)
- 下载完成系统通知、会话 Session Log、URL 拖拽输入
- ffmpeg / ffprobe 缺失时的明确提示
- SwiftFormat 配置与首次格式化。(#43)
- GitHub Release 在 asset 上传前自动创建。(#13)
- CI / Release Actions 升级至 Node 24 兼容版本。(#14)
- 工作流脚本 `fmt.sh` 和 `check_ci.sh`。(#17)
- Agent 角色定义与运行时权限治理框架。(#18, #20)

### Fixed
- 修复 per-item mapped 视频选择时强制转码的问题。(#39)
  > Why：播放列表逐条格式映射模式下不应对已选定的视频格式施加转码

---

## [0.0.5] — 2026-04-13

### Changed
- **GUI 框架切换**：从 PySide6（100–300MB）迁移到 pywebview + HTML/CSS/JS（< 20MB），使用 macOS 原生 WebKit 渲染。(#7)
  > Why：PySide6 体积过大且 QThread 在 Python 3.14 + PySide6 6.11 上存在 stall 问题
- 前端采用 Apple Design Language 重新设计：segmented controls、cards、light/dark 自动切换。(#7)
- **yt-dlp API 迁移**：format detection 和 downloader 从 subprocess 调用切换为 yt-dlp Python API，移除独立二进制打包路径。(#8, #9)
  > Why：API 调用省去进程启动开销，且避免了 PyInstaller 独立二进制在不同平台上的兼容问题

### Added
- ffmpeg license 声明文件。(#10)

### Fixed
- 修复 macOS ffprobe 未打包导致 `with_ffmpeg` 构建失败的问题。(#12)
- 修复 Windows 构建中 Python 解释器检测路径优先级错误。(#11)

---

## [0.0.4] — 2026-04-12

### Fixed
- 修复 Release workflow 中 macOS / Windows 各用错误 pip 安装命令的问题。(`b197ed5`)
- 简化 tag-triggered 发布的 publish 门禁条件。(`21e98a3`)

---

## [0.0.3] — 2026-04-12

### Fixed
- 修复 macOS Release 构建中二进制下载无重试导致偶发 CI 失败的问题。(`2f50bcb`)
- 修复 Windows Release job 依赖安装命令与 `py` launcher 不匹配的问题。(`9c65100`)

---

## [0.0.2] — 2026-04-12

### Added
- **Release pipeline**：tag-triggered CI 并行构建 macOS DMG + Windows EXE，自动上传至 GitHub Release。(#3)
- **ffmpeg 可选打包**：macOS / Windows 构建脚本支持 `WITH_FFMPEG=1` 开关。(`f493ff7`, `bfee0c7`)
- `pyproject.toml`、ruff + mypy 配置、GUI workers 测试，测试总数达 129。(`0a06d98`)

### Changed
- 仓库结构扁平化：`yt-tool/` 子目录提升至仓库根目录。(#6)
  > Why：单项目仓库中子目录增加了不必要的路径层级，且导致 `.github/workflows/` 位置错误从未被 CI 执行
- GUI UX 改进：窗口尺寸调整、QTreeWidget 格式列表、日志面板高度限制、Save directory picker。(#5)
- 修复 ruff 首次扫描发现的 26 处 lint 问题（此前 CI 从未运行过 ruff）。(#6)

### Fixed
- 修复 QThread stall 导致 GUI 控件永久禁用的问题：从 QObject + moveToThread 模式切换到 QThread 子类 + `run()` override。(#5)
  > Why：Python 3.14 + PySide6 6.11 下 AutoConnection / DirectConnection 传递 `quit()` 信号会 stall，`finished` 永不触发
- 修复 PyInstaller frozen mode 下相对 import 失败的问题。(`a003ea4`)
- 修复 `set_env_check_result` 中 `CheckResult.missing` 不存在的 AttributeError。(#4)
- 修复 app 退出时 QThread 未停止导致 SIGABRT crash 的问题。(`f8c6e28`)

---

## [0.0.1] — 2026-04-12

### Added
项目初始版本，Python CLI + PySide6 GUI：
- **CLI**：交互式 yt-dlp 前端，支持视频/音频格式选择、播放列表检测、下载归档、SponsorBlock 集成。(`ce4cc83`)
- **Core 分层**：`app/core/`（config、downloader、env_check、format_detector、path_utils）、`app/services/`（models、workflow）、`app/cli/`（main、ui）三层架构。(#1)
  > Why：为后续 GUI 层复用业务逻辑做准备，CLI 与 GUI 共享 core + services
- **GUI**：PySide6 Qt 桌面应用，workflow-driven 架构，Advanced Options 面板。(`e196ec0`, `23fbc00`)
- **格式预验证**：下载前通过 yt-dlp 验证候选格式可用性，codec 别名匹配（h264↔avc1 等）。(`ce4cc83`)
- **Playlist 支持**：all-video / all-audio / first-item 三种模式，per-URL+mode hash 防止归档冲突。(`ce4cc83`)
- **打包**：PyInstaller 构建脚本（macOS `.command` / Windows `.cmd` + `.ps1` launcher）。(`41782fc`)
- 55 个 CLI 单元测试 + CI workflow（pytest on Linux/macOS）。(`6645eb8`)

---

<!-- 版本对比链接 -->
[Unreleased]: https://github.com/Vyk3/yt-tool/compare/v0.1.3...HEAD
[0.1.3]: https://github.com/Vyk3/yt-tool/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/Vyk3/yt-tool/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/Vyk3/yt-tool/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Vyk3/yt-tool/compare/v0.0.5...v0.1.0
[0.0.5]: https://github.com/Vyk3/yt-tool/compare/v0.0.4...v0.0.5
[0.0.4]: https://github.com/Vyk3/yt-tool/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/Vyk3/yt-tool/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/Vyk3/yt-tool/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/Vyk3/yt-tool/releases/tag/v0.0.1
