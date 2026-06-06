# Changelog

本文档遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 格式，版本号遵循 [Semantic Versioning](https://semver.org/)。

---

## [Unreleased]

### Added
- **bilibili 反爬韧性**：`curlFetch` 新增最多 3 次指数退避重试（1s/2s/4s），不再立即抛错；所有 bilibili API 响应码输出到 Session Log（`FEED` scope），便于调试反爬状态；文件顶部文档化 4 种 TLS 指纹被封后的替代方案。(#85)

### Fixed
- **Playlist 下拉中文本地化**：6 个 playlist picker 从硬编码 `.title` 改为 `Loc` 本地化函数，中文模式下正确显示中文选项。(#83)
- **Retry 下载状态重置**：`retryDownload()` 现在先取消旧任务、作废旧 attemptID、重建 `ProcessRunner`，防止重试后进度卡住。(#83)
- **add-to-queue 失败不切 tab**：订阅页点加入队列失败时保持在当前 tab 并就地显示错误，不再无条件跳转到队列 tab。(#83)
- **bilibili arc/search feed + WBI 签名**：新增 `wbi/arc/search` 端点，通过 mixin key 排列 + MD5 签名获取频道全部投稿（不再仅限合集/系列）；-403 时带 stampede 保护刷新密钥；DecodingError 正确回落到 seasons 链路。(#82)
- **YouTube RSS 4xx 快速失败**：404 等客户端错误不再重试（省去 ~4s 无效等待），仅对 5xx / 网络错误重试。(#82)
- **下载进程竞态**：每次下载创建新 `ProcessRunner` 并显式终止上一个，杜绝遗留 yt-dlp 进程。(#82)
- **拖拽重排写入竞态**：`saveAsync()` 从 GCD 改为 `Task { @MainActor in save() }`，所有磁盘写入串行化，消除旧快照覆盖。(#82)
- **频道解析超时**：yt-dlp channel ID 解析增加 `--socket-timeout 15`。(#82)

---

## [0.2.2] — 2026-06-03

### Added
- **bilibili 订阅支持**：订阅 tab 支持添加 bilibili 频道（space URL 或视频 URL），自动解析 UP 主名称并轮询新视频。(#78)
- **Platform 枚举**：`ChannelSubscription` 新增 `.youtube` / `.bilibili` 平台标识，URL 自动检测，Codable 向后兼容。(#78)
- **BilibiliFeedService**：独立的 bilibili 频道解析和视频拉取服务（actor），使用 curl 子进程绕过 TLS 指纹检测。(#78)
- **API fallback 链路**：card API 被限流时自动降级到 seasons → view API 链路获取 UP 主名称。(#78)
- **bilibili 单元测试**：新增 12 个测试覆盖响应解析、平台检测、Codable 往返、缩略图 URL 规范化。(#78)

---

## [0.2.1] — 2026-06-02

### Fixed
- **Sparkle 更新弹窗语言同步**：添加 `zh-Hans` 到 `knownRegions`，在 app 启动时同步 `AppleLanguages`，Sparkle 更新弹窗语言跟随应用内语言设置。(#73)
- **hardcoded 字符串本地化**：10 处 Picker label、ETA、ffmpeg 缺失提示、文件夹选择按钮从硬编码英文改为 `Loc` 双语支持。(#73)
- **DownloadQueue force unwrap**：`processItem` 中消除 `item.runner!`，改用局部变量传递。(#73)
- **debug print 清理**：移除 `requestNotificationPermission` 中的调试输出。(#73)

---

## [0.2.0] — 2026-06-02

### Added
- **完整双语本地化**：新增 `Localization.swift`，所有 UI 字符串支持中文和英文切换。(#67)
- **Settings 三列布局**：重写 `SettingsTabView` 为紧凑三列布局（分区 | 标题 | 控件），列宽随语言自适应。(#67)
- **开发构建脚本**：新增 `dev_launch.sh`，自动编译并启动 app bundle。(#67)
- **FeedVideo 持久化测试**：新增 `FeedVideoPersistenceTests` 覆盖订阅视频数据往返。(#67)
- **视频缩略图**：队列和订阅列表显示视频缩略图及时长徽章，支持 YouTube 直出和 Bilibili API 解析，异步加载带内存/磁盘双层缓存。(#70)
- **格式筛选**：Format Picker 新增按分辨率、编码、文件大小等条件筛选，技术详情默认折叠。(#70)
- **Cookies 使用指南**：Settings 中新增 Cookies 获取步骤弹窗，中英文自适应。(#70)
- **隐私说明弹窗**：About 区域新增隐私说明，说明数据仅保留本地。(#70)

### Changed
- 最低系统要求从 macOS 13 提升至 macOS 14。(#70)
  > Why：NSImage 的 Sendable conformance 在 macOS 14+ 才可用，Swift 6 strict concurrency 下无法兼容 macOS 13
- **ProcessRunner UTF-8 安全解码**：引入 `UTF8LineBuffer`，在 `readabilityHandler` 层缓冲不完整的 multi-byte UTF-8 序列，仅在字节完整时才解码为 String。(#68)
  > Why：原 `String(decoding:as:)` 对 pipe 读取边界上被拆分的 CJK / emoji 字符替换为 U+FFFD（替换字符），下游 `run()` 的 Data 累积无法修复已损坏的数据
- **ProcessRunner trailing bytes 简化**：`terminationHandler` 中 `readDataToEndOfFile()` 的数据现作为正常 `.stdout`/`.stderr` 事件 yield，而非通过 `ProcessResult` 额外字段传递。移除 `trailingStdout`/`trailingStderr` 字段、自定义 `==` 和 `run()` 中的合并逻辑，净减约 20 行。(#68)
  > Why：原设计将 `run()` 内部关注点泄漏到 `ProcessResult` 公共接口，且 `stream()` 的直接消费者看不到 trailing bytes
- **订阅 URL 输入持久化**：`newChannelURL` 从 `SubscriptionsView` 的 `@State` 迁移为 `AppState` 的 `@Published`，通过 `@Binding` 传递，切换标签页后输入内容不再丢失。(#68)
  > Why：SwiftUI `@State` 在 `switch` 条件渲染中会随视图销毁重建而重置
- **probe 可靠性**：`ProbeParser.formats` 改为 optional，新增详细 `DecodingError` 报告。(#67)
- **格式表格水平滚动**：技术详情模式下格式表格增加 `ScrollView` 水平滚动。(#67)
- **标签页内容宽度约束**：队列（700pt）和订阅（600pt）标签页增加 `maxWidth` 约束，低内容量时信息密度更佳。(#67)
- Cookies 路径在日志中脱敏，同时支持 `--cookies path` 和 `--cookies=path` 两种形式。(#70)
- `addSingleURLToQueue` 失败时设置 `queueError` 并记录日志，不再静默吞没错误。(#70)
- 订阅页"添加到队列"失败后自动切换到队列页，确保用户能看到错误提示。(#70)

### Removed
- 移除隐私说明中"源代码完全开放"条目（与 GitHub 链接重复，对非技术用户无意义）。(#70)
- 移除死代码：`releasesLink()`、`DownloadQueue.moveItem()`。(#70)

### Fixed
- **相对时间戳语言匹配**：`Text(date, style: .relative)` 增加 `.environment(\.locale, language.locale)`，订阅页面的相对时间显示随 app 语言切换，不再跟随系统 locale。(#68)
- **队列列表溢出**：`QueueView` 限制 `minHeight` 不超过 `maxHeight`（300pt），6 个以上项目时不再撑破容器。(#67)
- **本地化遗漏**：订阅页删除确认弹窗的 "Cancel" 改用 `Loc.cancelButton()`；历史页取消按钮改用 `Loc.cancelButton()` 替换 `Loc.done()`。(#67)
- **通知正文重复**：`AppState` 通知 body 使用 `Loc.notificationBody()` 替换错误复用的 `Loc.notificationTitle()`。(#67)
- **标签页切换状态丢失**：移除 `ContentView` 中的 `.id(state.appMode)`，该修饰符导致切换标签页时子视图 `@State` 被销毁重建。(#67)
- **dev_launch.sh 陈旧构建**：通过 `PIPESTATUS[0]` 捕获 xcodebuild 退出码，编译失败时不再静默启动上一次成功构建的 `.app`。(#67)
- **死代码清理**：移除零引用的 `UpdateView.swift` 和 `AdvancedOptionsView.swift`。(#67)
- 修复 Swift 6 strict concurrency 下 `NSImage` 跨 actor 边界的编译错误（`SendableImage` wrapper）。(#70)
- 修复 `onChange(of:)` 在 macOS 14 下的弃用警告。(#70)

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
[Unreleased]: https://github.com/Vyk3/yt-tool/compare/v0.2.2...HEAD
[0.2.2]: https://github.com/Vyk3/yt-tool/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/Vyk3/yt-tool/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/Vyk3/yt-tool/compare/v0.1.5...v0.2.0
[0.1.5]: https://github.com/Vyk3/yt-tool/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/Vyk3/yt-tool/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/Vyk3/yt-tool/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/Vyk3/yt-tool/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/Vyk3/yt-tool/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Vyk3/yt-tool/compare/v0.0.5...v0.1.0
[0.0.5]: https://github.com/Vyk3/yt-tool/compare/v0.0.4...v0.0.5
[0.0.4]: https://github.com/Vyk3/yt-tool/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/Vyk3/yt-tool/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/Vyk3/yt-tool/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/Vyk3/yt-tool/releases/tag/v0.0.1
