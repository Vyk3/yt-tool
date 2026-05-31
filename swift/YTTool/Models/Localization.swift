import Foundation

// MARK: - Language enum

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    /// Display name shown in the language picker — always in the target language.
    var displayName: String {
        switch self {
        case .english: "English"
        case .chinese: "中文"
        }
    }
}

// MARK: - Localized strings

/// Centralised string table. Every user-visible label goes through here.
/// Convention: each function takes `AppLanguage` as the last parameter, abbreviated `l`.
enum Loc {

    // MARK: Tabs

    static func tabLabel(_ mode: AppMode, _ l: AppLanguage) -> String {
        switch (mode, l) {
        case (.single, .english): "Single"
        case (.single, .chinese): "单个"
        case (.queue, .english): "Queue"
        case (.queue, .chinese): "队列"
        case (.subscriptions, .english): "Subs"
        case (.subscriptions, .chinese): "订阅"
        case (.settings, .english): "Settings"
        case (.settings, .chinese): "设置"
        }
    }

    static func headerSubtitle(_ mode: AppMode, _ l: AppLanguage) -> String {
        switch (mode, l) {
        case (.single, .english):
            "Enter a video URL and press Probe to inspect available formats."
        case (.single, .chinese):
            "输入视频 URL，点按「探测」查看可用格式。"
        case (.queue, .english):
            "Paste URLs (one per line) and add them to the download queue."
        case (.queue, .chinese):
            "粘贴 URL（每行一个），添加到下载队列。"
        case (.subscriptions, .english):
            "Subscribe to channels and get notified when new videos are uploaded."
        case (.subscriptions, .chinese):
            "订阅频道，新视频上传时接收通知。"
        case (.settings, .english):
            "Configure download options, subscriptions, and updates."
        case (.settings, .chinese):
            "配置下载选项、订阅和更新。"
        }
    }

    // MARK: Common

    static func history(_ l: AppLanguage) -> String { l == .chinese ? "历史" : "History" }

    // MARK: Subscriptions view

    static func channelURLPlaceholder(_ l: AppLanguage) -> String {
        l == .chinese ? "YouTube 频道或视频 URL" : "YouTube channel or video URL"
    }
    static func subscribe(_ l: AppLanguage) -> String { l == .chinese ? "订阅" : "Subscribe" }
    static func newVideos(_ l: AppLanguage) -> String { l == .chinese ? "新视频" : "New Videos" }
    static func dismissAll(_ l: AppLanguage) -> String { l == .chinese ? "全部忽略" : "Dismiss All" }
    static func channels(_ l: AppLanguage) -> String { l == .chinese ? "频道" : "Channels" }
    static func checkNow(_ l: AppLanguage) -> String { l == .chinese ? "立即检查" : "Check Now" }
    static func selectAction(_ l: AppLanguage) -> String { l == .chinese ? "选择" : "Select" }
    static func done(_ l: AppLanguage) -> String { l == .chinese ? "完成" : "Done" }
    static func deleteLabel(_ l: AppLanguage) -> String { l == .chinese ? "删除" : "Delete" }
    static func noSubscriptionsTitle(_ l: AppLanguage) -> String {
        l == .chinese ? "暂无订阅" : "No subscriptions yet"
    }
    static func noSubscriptionsHint(_ l: AppLanguage) -> String {
        l == .chinese ? "在上方输入频道 URL 即可开始。" : "Add a channel URL above to get started."
    }
    static func deleteSubscriptionsTitle(_ l: AppLanguage) -> String {
        l == .chinese ? "删除订阅" : "Delete Subscriptions"
    }
    static func deleteNChannels(_ n: Int, _ l: AppLanguage) -> String {
        l == .chinese
            ? "删除 \(n) 个频道"
            : "Delete \(n) channel\(n == 1 ? "" : "s")"
    }
    static func removeConfirmation(_ names: String, _ l: AppLanguage) -> String {
        l == .chinese ? "确定移除 \(names)？" : "Remove \(names)?"
    }
    static func copyAllURLs(_ l: AppLanguage) -> String { l == .chinese ? "复制全部链接" : "Copy All URLs" }
    static func copyURLHelp(_ l: AppLanguage) -> String { l == .chinese ? "复制视频链接" : "Copy video URL" }
    static func checkedPrefix(_ l: AppLanguage) -> String { l == .chinese ? "已检查 · " : "Checked " }
    static func checkedSuffix(_ l: AppLanguage) -> String { l == .chinese ? "" : " ago" }

    // MARK: Settings sections

    static func sectionDownload(_ l: AppLanguage) -> String { l == .chinese ? "下载" : "Download" }
    static func sectionSubscriptions(_ l: AppLanguage) -> String { l == .chinese ? "订阅" : "Subscriptions" }
    static func sectionUpdates(_ l: AppLanguage) -> String { l == .chinese ? "更新" : "Updates" }
    static let sectionYtDlp = "yt-dlp"

    // Poll interval labels
    static func interval15min(_ l: AppLanguage) -> String { l == .chinese ? "15 分钟" : "15 min" }
    static func interval30min(_ l: AppLanguage) -> String { l == .chinese ? "30 分钟" : "30 min" }
    static func interval1hour(_ l: AppLanguage) -> String { l == .chinese ? "1 小时" : "1 hour" }
    static func interval2hours(_ l: AppLanguage) -> String { l == .chinese ? "2 小时" : "2 hours" }
    static func sectionAppUpdates(_ l: AppLanguage) -> String { l == .chinese ? "应用更新" : "App Updates" }
    static func sectionAbout(_ l: AppLanguage) -> String { l == .chinese ? "关于" : "About" }
    static func sectionLanguage(_ l: AppLanguage) -> String { l == .chinese ? "显示" : "Display" }

    // MARK: Settings rows

    static func downloadEngine(_ l: AppLanguage) -> String { l == .chinese ? "下载引擎" : "Download engine" }
    static func aria2cNotFound(_ l: AppLanguage) -> String {
        l == .chinese
            ? "未找到 aria2c — 可通过 brew install aria2 安装"
            : "aria2c not found — install via: brew install aria2"
    }
    static func cookiesFile(_ l: AppLanguage) -> String { l == .chinese ? "Cookies 文件" : "Cookies file" }
    static func cookiesDescription(_ l: AppLanguage) -> String {
        l == .chinese ? "可选。路径必须存在且可读。" : "Optional. The path must exist and be readable."
    }
    static func extraArgs(_ l: AppLanguage) -> String {
        l == .chinese ? "额外 yt-dlp 参数" : "Extra yt-dlp arguments"
    }
    static func extraArgsDescription(_ l: AppLanguage) -> String {
        l == .chinese ? "可选。验证后透传给 yt-dlp。" : "Optional. Passed through after validation."
    }
    static func checkInterval(_ l: AppLanguage) -> String { l == .chinese ? "检查间隔" : "Check interval" }
    static func checkIntervalDescription(_ l: AppLanguage) -> String {
        l == .chinese ? "轮询订阅频道新视频的频率。" : "How often to poll subscribed channels for new uploads."
    }
    static func automaticChecks(_ l: AppLanguage) -> String { l == .chinese ? "自动检查" : "Automatic checks" }
    static func automaticChecksDescription(_ l: AppLanguage) -> String {
        l == .chinese ? "启动时检查应用更新。" : "Check for app updates on launch."
    }
    static func checkForAppUpdates(_ l: AppLanguage) -> String {
        l == .chinese ? "检查应用更新" : "Check for App Updates"
    }
    static func ytDlpDependency(_ l: AppLanguage) -> String { l == .chinese ? "依赖：yt-dlp" : "Dependency: yt-dlp" }
    static func ytDlpDescription(_ l: AppLanguage) -> String {
        l == .chinese ? "YouTube 视频下载引擎（第三方）" : "Video download engine (third-party)"
    }
    static func audioTranscodeKeepOriginal(_ l: AppLanguage) -> String {
        l == .chinese ? "保持原始" : "Keep original"
    }
    static func audioTranscodeLocalized(_ format: AudioTranscodeFormat, _ l: AppLanguage) -> String {
        switch format {
        case .original: audioTranscodeKeepOriginal(l)
        case .mp3: "MP3"
        case .m4a: "M4A"
        case .wav: "WAV"
        }
    }
    static func appUpdateLabel(_ l: AppLanguage) -> String { l == .chinese ? "应用更新" : "App update" }
    static func appVersionLabel(_ l: AppLanguage) -> String { l == .chinese ? "应用版本" : "App version" }
    static func buildLabel(_ l: AppLanguage) -> String { l == .chinese ? "构建号" : "Build" }
    static func repositoryLink(_ l: AppLanguage) -> String { l == .chinese ? "仓库" : "Repository" }
    static func releasesLink(_ l: AppLanguage) -> String { l == .chinese ? "发布" : "Releases" }
    static func languageLabel(_ l: AppLanguage) -> String { l == .chinese ? "语言" : "Language" }
    static func languageDescription(_ l: AppLanguage) -> String {
        l == .chinese ? "切换界面显示语言。" : "Switch the display language."
    }
    static func appearanceLabel(_ l: AppLanguage) -> String { l == .chinese ? "外观" : "Appearance" }
    static func technicalDetails(_ l: AppLanguage) -> String { l == .chinese ? "技术详情" : "Technical details" }
    static func technicalDetailsHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "在格式列表中显示 ID、编码、FPS、码率等详细列" : "Show ID, codec, FPS, bitrate columns in format lists"
    }
    static func appearanceTitle(_ a: AppAppearance, _ l: AppLanguage) -> String {
        switch (a, l) {
        case (.system, .chinese): "跟随系统"
        case (.system, .english): "System"
        case (.light, .chinese): "浅色"
        case (.light, .english): "Light"
        case (.dark, .chinese): "深色"
        case (.dark, .english): "Dark"
        }
    }

    // MARK: Update view

    static func currentVersionLabel(_ l: AppLanguage) -> String { l == .chinese ? "当前版本" : "Current version" }
    static func channelLabel(_ l: AppLanguage) -> String { l == .chinese ? "更新通道" : "Channel" }
    static func autoCheckYtDlp(_ l: AppLanguage) -> String {
        l == .chinese ? "启动时检查 yt-dlp 更新" : "Auto-check yt-dlp updates"
    }
    static func checkForUpdates(_ l: AppLanguage) -> String { l == .chinese ? "检查更新" : "Check for Updates" }
    static func checking(_ l: AppLanguage) -> String { l == .chinese ? "检查中…" : "Checking..." }
    static func updateAvailable(_ current: String, _ latest: String, _ l: AppLanguage) -> String {
        l == .chinese ? "有可用更新：\(current) → \(latest)" : "Update available: \(current) → \(latest)"
    }
    static func installUpdate(_ l: AppLanguage) -> String { l == .chinese ? "安装更新" : "Install Update" }
    static func upToDate(_ version: String, _ l: AppLanguage) -> String {
        l == .chinese ? "已是最新 (\(version))" : "Up to date (\(version))"
    }
    static func checkAgain(_ l: AppLanguage) -> String { l == .chinese ? "再次检查" : "Check Again" }
    static func downloadingUpdate(_ l: AppLanguage) -> String { l == .chinese ? "下载中…" : "Downloading..." }
    static func verifyingInstalling(_ l: AppLanguage) -> String {
        l == .chinese ? "验证并安装中…" : "Verifying and installing..."
    }
    static func updatedTo(_ version: String, _ l: AppLanguage) -> String {
        l == .chinese ? "已更新至 \(version)" : "Updated to \(version)"
    }
    static func retry(_ l: AppLanguage) -> String { l == .chinese ? "重试" : "Retry" }

    // MARK: URL input view

    static func urlHeading(_ l: AppLanguage) -> String { "URL" }
    static func dragHint(_ l: AppLanguage) -> String {
        l == .chinese ? "你也可以将视频 URL 拖放到输入框中。" : "You can also drag a video URL into the field."
    }
    static func probeButton(_ l: AppLanguage) -> String { l == .chinese ? "探测" : "Probe" }
    static func probeFirstItem(_ l: AppLanguage) -> String { l == .chinese ? "探测第一个" : "Probe first item" }
    static func statusIdle(_ l: AppLanguage) -> String { l == .chinese ? "空闲" : "Idle" }
    static func statusProbing(_ l: AppLanguage) -> String { l == .chinese ? "探测中…" : "Probing…" }
    static func statusReady(_ title: String, _ l: AppLanguage) -> String {
        l == .chinese ? "就绪：\(title)" : "Ready: \(title)"
    }
    static func chooseFolderHint(_ l: AppLanguage) -> String { l == .chinese ? "选择文件夹…" : "Choose folder…" }
    static func clearFolderHelp(_ l: AppLanguage) -> String { l == .chinese ? "清除所选文件夹" : "Clear selected folder" }

    // Playlist mode
    static func playlistMode(_ l: AppLanguage) -> String { l == .chinese ? "播放列表模式" : "Playlist mode" }
    static func playlistModeHintFirst(_ l: AppLanguage) -> String {
        l == .chinese ? "仅探测第一个项目，然后像单个视频一样下载。" : "Probe inspects only the first item, then downloads it like a single video."
    }
    static func playlistModeHintWhole(_ l: AppLanguage) -> String {
        l == .chinese ? "整个播放列表会自动下载所有项目。" : "Whole playlist downloads every item automatically."
    }
    static func videoQuality(_ l: AppLanguage) -> String { l == .chinese ? "视频质量" : "Video quality" }
    static func videoQualityHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "选择整个播放列表的视频下载偏好兼容性或更高质量。" : "Choose whether whole-playlist video downloads favor compatibility or higher quality."
    }
    static func audioQuality(_ l: AppLanguage) -> String { l == .chinese ? "音频质量" : "Audio quality" }
    static func audioQualityHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "选择整个播放列表的音频下载偏好兼容性或更高质量。" : "Choose whether whole-playlist audio downloads favor compatibility or higher quality."
    }
    static func playlistFormats(_ l: AppLanguage) -> String { l == .chinese ? "播放列表格式" : "Playlist formats" }
    static func playlistFormatsHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "使用统一策略下载所有项目，或为特定项目指定格式。" : "Use a single strategy for all items, or map specific items to specific format selectors."
    }
    static func perItemMap(_ l: AppLanguage) -> String { l == .chinese ? "逐项映射" : "Per-item map" }
    static func perItemMapHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "语法：项目索引=格式选择器;项目索引=格式选择器。" : "Syntax: itemIndex=formatSelector;itemIndex=formatSelector."
    }
    static func playlistSubtitles(_ l: AppLanguage) -> String { l == .chinese ? "播放列表字幕" : "Playlist subtitles" }
    static func playlistSubtitlesHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "为播放列表中的每个项目应用相同的字幕策略。" : "Apply the same subtitle strategy to each item in the playlist."
    }
    static func subtitleLanguageLabel(_ l: AppLanguage) -> String { l == .chinese ? "字幕语言" : "Subtitle language" }
    static func subtitleLanguageHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "用作整个播放列表下载的 --sub-langs 参数。" : "Used as --sub-langs for whole-playlist downloads."
    }
    static func playlistSegments(_ l: AppLanguage) -> String { l == .chinese ? "播放列表片段" : "Playlist segments" }
    static func playlistSegmentsHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "选择每个项目是完整下载还是指定时间范围。" : "Choose whether each item downloads fully or with a fixed time range."
    }
    static func timeRange(_ l: AppLanguage) -> String { l == .chinese ? "时间范围" : "Time range" }
    static func timeRangeHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "传递为 --download-sections *<范围>。" : "Passed as --download-sections *<range>."
    }

    // MARK: Format picker view

    static func formatsHeading(_ l: AppLanguage) -> String { l == .chinese ? "格式" : "Formats" }
    static func videoLabel(_ l: AppLanguage) -> String { l == .chinese ? "视频" : "Video" }
    static func audioLabel(_ l: AppLanguage) -> String { l == .chinese ? "音频" : "Audio" }
    static func subtitlesLabel(_ l: AppLanguage) -> String { l == .chinese ? "字幕" : "Subtitles" }
    static func manualSubs(_ l: AppLanguage) -> String { l == .chinese ? "手动" : "Manual" }
    static func autoSubs(_ l: AppLanguage) -> String { l == .chinese ? "自动生成" : "Auto-generated" }
    static func loadingFormats(_ l: AppLanguage) -> String { l == .chinese ? "加载格式中…" : "Loading formats…" }
    static func probeToInspect(_ l: AppLanguage) -> String {
        l == .chinese ? "探测 URL 以查看可用格式。" : "Probe a URL to inspect available formats."
    }
    static func probeFirstToInspect(_ l: AppLanguage) -> String {
        l == .chinese ? "探测第一个项目以查看格式。" : "Probe the first item to inspect formats."
    }
    static func wholePlaylistSkips(_ l: AppLanguage) -> String {
        l == .chinese ? "整个播放列表模式跳过逐项格式选择，自动下载所有项目。" : "Whole playlist mode skips per-item format selection and downloads every item automatically."
    }
    static func wholePlaylistAuto(_ l: AppLanguage) -> String {
        l == .chinese ? "整个播放列表模式自动下载所有项目。" : "Whole playlist mode downloads every item automatically."
    }
    static func noVideoFormats(_ l: AppLanguage) -> String { l == .chinese ? "未检测到视频格式。" : "No video formats detected." }
    static func noAudioFormats(_ l: AppLanguage) -> String { l == .chinese ? "未检测到音频格式。" : "No audio formats detected." }

    // MARK: Download progress view

    static func downloadHeading(_ l: AppLanguage) -> String { l == .chinese ? "下载" : "Download" }
    static func cancelButton(_ l: AppLanguage) -> String { l == .chinese ? "取消" : "Cancel" }
    static func downloadButton(_ l: AppLanguage) -> String { l == .chinese ? "下载" : "Download" }
    static func readyToDownload(_ l: AppLanguage) -> String {
        l == .chinese ? "准备就绪。点按「下载」开始。" : "Ready to download. Press Download to start."
    }
    static func selectFormatHint(_ l: AppLanguage) -> String {
        l == .chinese ? "选择格式和输出文件夹以启用下载。" : "Select a format and output folder to enable download."
    }
    static func noFormatsCanDownload(_ l: AppLanguage) -> String {
        l == .chinese
            ? "未显示可选格式，将尝试兜底下载（best）。"
            : "No selectable formats found; will attempt fallback download (best)."
    }
    static func noFormatsNeedFolder(_ l: AppLanguage) -> String {
        l == .chinese
            ? "未显示可选格式。请先选择输出文件夹；若已选择，请重试探测或查看日志。"
            : "No selectable formats. Select an output folder first; if already selected, retry Probe or check logs."
    }
    static func stagePreparing(_ l: AppLanguage) -> String { l == .chinese ? "准备中" : "Preparing" }
    static func stagePreparingSub(_ l: AppLanguage) -> String {
        l == .chinese ? "正在构建 yt-dlp 命令并启动进程。" : "Building the yt-dlp command and starting the process."
    }
    static func stageDownloading(_ l: AppLanguage) -> String { l == .chinese ? "下载中" : "Downloading" }
    static func stageDownloadingSub(_ l: AppLanguage) -> String {
        l == .chinese ? "传输正在进行中。" : "The active transfer is in progress."
    }
    static func stageCompleted(_ l: AppLanguage) -> String { l == .chinese ? "完成 ✓" : "Completed ✓" }
    static func stageCompletedSubFile(_ l: AppLanguage) -> String {
        l == .chinese ? "选择对下载文件的操作。" : "Choose what to do with the finished file."
    }
    static func stageCompletedSubDir(_ l: AppLanguage) -> String {
        l == .chinese ? "选择对下载项目的操作。" : "Choose what to do with the downloaded items."
    }
    static func stageFailed(_ l: AppLanguage) -> String { l == .chinese ? "失败" : "Failed" }
    static func stageFailedSub(_ l: AppLanguage) -> String {
        l == .chinese ? "下载在完成前中断。" : "The download stopped before completion."
    }
    static func stageCancelled(_ l: AppLanguage) -> String { l == .chinese ? "已取消" : "Cancelled" }
    static func stageCancelledSub(_ l: AppLanguage) -> String {
        l == .chinese ? "活动进程已终止。" : "The active process tree was terminated."
    }
    static func cancelledHint(_ l: AppLanguage) -> String {
        l == .chinese ? "你可以调整格式或输出文件夹，然后开始新的下载。" : "You can adjust the format or output folder, then start a new download."
    }
    static func revealInFinder(_ l: AppLanguage) -> String { l == .chinese ? "在 Finder 中显示" : "Reveal in Finder" }
    static func openFolder(_ l: AppLanguage) -> String { l == .chinese ? "打开文件夹" : "Open Folder" }
    static func copyFilePath(_ l: AppLanguage) -> String { l == .chinese ? "复制文件路径" : "Copy File Path" }
    static func copyFolderPath(_ l: AppLanguage) -> String { l == .chinese ? "复制文件夹路径" : "Copy Folder Path" }
    static func newDownload(_ l: AppLanguage) -> String { l == .chinese ? "新的下载" : "New Download" }
    static func reasonLabel(_ l: AppLanguage) -> String { l == .chinese ? "原因" : "Reason" }
    static func tryThisLabel(_ l: AppLanguage) -> String { l == .chinese ? "建议" : "Try this" }
    static func ffmpegUnavailable(_ l: AppLanguage) -> String { l == .chinese ? "FFmpeg 不可用" : "FFmpeg unavailable" }
    static func sizeLabel(_ l: AppLanguage) -> String { l == .chinese ? "大小" : "Size" }
    static func speedLabel(_ l: AppLanguage) -> String { l == .chinese ? "速度" : "Speed" }

    // MARK: Advanced options view

    static func advancedOptions(_ l: AppLanguage) -> String {
        l == .chinese ? "高级选项（可选）" : "Advanced options (optional)"
    }
    static func audioTranscode(_ l: AppLanguage) -> String { l == .chinese ? "音频转码" : "Audio transcode" }
    static func cookiesSet(_ l: AppLanguage) -> String { l == .chinese ? "Cookies 已设置" : "Cookies set" }
    static func extraArgsSet(_ l: AppLanguage) -> String { l == .chinese ? "额外参数已设置" : "Extra args set" }
    static func changeInSettings(_ l: AppLanguage) -> String {
        l == .chinese ? "在设置标签页中修改" : "Change in Settings tab"
    }

    // MARK: Log panel view

    static func sessionLog(_ l: AppLanguage) -> String { l == .chinese ? "会话日志" : "Session Log" }
    static func nEntries(_ n: Int, _ l: AppLanguage) -> String {
        l == .chinese ? "\(n) 条" : "\(n) entries"
    }
    static func showLogs(_ l: AppLanguage) -> String { l == .chinese ? "展开日志" : "Show Logs" }
    static func hideLogs(_ l: AppLanguage) -> String { l == .chinese ? "收起日志" : "Hide Logs" }
    static func latestActivity(_ l: AppLanguage) -> String { l == .chinese ? "最近活动" : "Latest activity" }
    static func logPlaceholder(_ l: AppLanguage) -> String {
        l == .chinese ? "探测和下载事件将在此会话期间显示在这里。" : "Probe and download events will appear here during this app session."
    }

    // MARK: History view

    static func downloadHistory(_ l: AppLanguage) -> String { l == .chinese ? "下载历史" : "Download History" }
    static func clearAll(_ l: AppLanguage) -> String { l == .chinese ? "全部清除" : "Clear All" }
    static func noDownloadsYet(_ l: AppLanguage) -> String { l == .chinese ? "暂无下载记录。" : "No downloads yet." }
    static func reveal(_ l: AppLanguage) -> String { l == .chinese ? "显示" : "Reveal" }

    // MARK: Queue view (ContentView inline)

    static func urlsPerLine(_ l: AppLanguage) -> String { l == .chinese ? "URL（每行一个）" : "URLs (one per line)" }
    static func importButton(_ l: AppLanguage) -> String { l == .chinese ? "导入" : "Import" }
    static func pasteButton(_ l: AppLanguage) -> String { l == .chinese ? "粘贴" : "Paste" }
    static func addToQueue(_ l: AppLanguage) -> String { l == .chinese ? "添加到队列" : "Add to Queue" }
    static func estimated(_ total: String, _ detail: String, _ l: AppLanguage) -> String {
        l == .chinese ? "预估：\(total)\(detail)" : "Estimated: \(total)\(detail)"
    }

    // MARK: Queue view (QueueView + QueueItemRow)

    static func queueCount(_ n: Int, _ l: AppLanguage) -> String {
        l == .chinese ? "队列（\(n) 项）" : "Queue (\(n) items)"
    }
    static func queueStop(_ l: AppLanguage) -> String { l == .chinese ? "停止" : "Stop" }
    static func queueStart(_ l: AppLanguage) -> String { l == .chinese ? "开始" : "Start" }
    static func queueClearDone(_ l: AppLanguage) -> String { l == .chinese ? "清除已完成" : "Clear done" }
    static func queueEmpty(_ l: AppLanguage) -> String {
        l == .chinese
            ? "队列为空。在上方粘贴 URL 并点击「添加到队列」。"
            : "No items in queue. Paste URLs above and click Add to Queue."
    }
    static func queuePending(_ l: AppLanguage) -> String { l == .chinese ? "等待中" : "Pending" }
    static func queueStarting(_ l: AppLanguage) -> String { l == .chinese ? "启动中…" : "Starting..." }
    static func queueCompleted(_ l: AppLanguage) -> String { l == .chinese ? "已完成" : "Completed" }
    static func queueItemFailed(_ l: AppLanguage) -> String { l == .chinese ? "失败" : "Failed" }
    static func queueItemCancelled(_ l: AppLanguage) -> String { l == .chinese ? "已取消" : "Cancelled" }
    static func queueRemoveHelp(_ l: AppLanguage) -> String { l == .chinese ? "从队列中移除" : "Remove from queue" }
    static func queueCancelHelp(_ l: AppLanguage) -> String { l == .chinese ? "取消下载" : "Cancel download" }
    static func queueRetryHelp(_ l: AppLanguage) -> String { l == .chinese ? "重试" : "Retry" }
    static func queueNeedFolder(_ l: AppLanguage) -> String {
        l == .chinese ? "请先选择输出文件夹再添加到队列。" : "Select an output folder before adding to queue."
    }
    static func queueProgress(_ completed: Int, _ total: Int, _ failed: Int, _ l: AppLanguage) -> String {
        if l == .chinese {
            var s = "\(completed)/\(total) 已完成"
            if failed > 0 { s += "，\(failed) 失败" }
            return s
        } else {
            var s = "\(completed)/\(total) completed"
            if failed > 0 { s += ", \(failed) failed" }
            return s
        }
    }

    // Queue quality strategy
    static func qualityBest(_ l: AppLanguage) -> String { l == .chinese ? "最佳质量" : "Best quality" }
    static func qualityMax1080(_ l: AppLanguage) -> String { l == .chinese ? "最高 1080p" : "1080p max" }
    static func qualityMax720(_ l: AppLanguage) -> String { l == .chinese ? "最高 720p" : "720p max" }
    static func qualityAudioOnly(_ l: AppLanguage) -> String { l == .chinese ? "仅音频" : "Audio only" }
    static func qualityLabel(_ l: AppLanguage) -> String { l == .chinese ? "质量" : "Quality" }

    static func qualityTitle(_ strategy: QueueQualityStrategy, _ l: AppLanguage) -> String {
        switch strategy {
        case .bestQuality: qualityBest(l)
        case .max1080p: qualityMax1080(l)
        case .max720p: qualityMax720(l)
        case .audioOnly: qualityAudioOnly(l)
        }
    }

    // MARK: Format note localization (#6)

    static func videoNote(_ note: String, _ l: AppLanguage) -> String {
        guard l == .chinese else { return note }
        switch note.lowercased() {
        case "w/ audio": return "含音频"
        case "no audio": return "仅视频"
        default: return note
        }
    }

    static func audioNote(_ note: String, _ l: AppLanguage) -> String {
        if l == .chinese {
            switch note.lowercased() {
            case "ultralow": return "极低"
            case "low": return "基础"
            case "medium": return "标准"
            case "high": return "高"
            default: return note
            }
        } else {
            switch note.lowercased() {
            case "ultralow": return "Minimal"
            case "low": return "Basic"
            case "medium": return "Standard"
            case "high": return "High"
            default: return note
            }
        }
    }

    /// Simplified mode: descriptive label + bitrate for audio quality.
    static func audioQualityBrief(_ note: String, kbps: Double?, _ l: AppLanguage) -> String {
        let label = audioNote(note, l)
        if let kbps {
            return "\(label) · \(Int(kbps))k"
        }
        // Known quality descriptors are useful without bitrate; raw technical notes
        // (e.g. "DASH audio") are not — show "—" instead.
        let knownLabels: Set = ["极低", "基础", "标准", "高", "Minimal", "Basic", "Standard", "High"]
        return knownLabels.contains(label) ? label : "—"
    }

    // MARK: Retry download (#2)

    static func retryDownload(_ l: AppLanguage) -> String { l == .chinese ? "重新下载" : "Retry Download" }

    // MARK: Precise download disabled reason (#3)

    static func needFolderHint(_ l: AppLanguage) -> String {
        l == .chinese ? "请选择输出文件夹以启用下载。" : "Select an output folder to enable download."
    }
    static func needFormatHint(_ l: AppLanguage) -> String {
        l == .chinese ? "请选择至少一个格式以启用下载。" : "Select at least one format to enable download."
    }

    // MARK: Add video to queue from subscriptions (#4)

    static func addVideoToQueue(_ l: AppLanguage) -> String { l == .chinese ? "加入队列" : "Add to Queue" }
    static func addedToQueueInput(_ l: AppLanguage) -> String {
        l == .chinese ? "已添加到队列输入" : "Added to queue input"
    }

    // MARK: Format picker column headers (#6)

    static func colRes(_ l: AppLanguage) -> String { l == .chinese ? "分辨率" : "Res" }
    static func colCodec(_ l: AppLanguage) -> String { l == .chinese ? "编码" : "Codec" }
    static func colBitrate(_ l: AppLanguage) -> String { l == .chinese ? "码率" : "Bitrate" }
    static func colSize(_ l: AppLanguage) -> String { l == .chinese ? "大小" : "Size" }
    static func colNote(_ l: AppLanguage) -> String { l == .chinese ? "备注" : "Note" }

    // MARK: Log error badge (#8)

    static func errorBadge(_ n: Int, _ l: AppLanguage) -> String {
        l == .chinese ? "\(n) 个错误" : "\(n) error\(n == 1 ? "" : "s")"
    }

    // MARK: History clear confirmation (#9)

    static func clearHistoryTitle(_ l: AppLanguage) -> String { l == .chinese ? "确认清除" : "Clear History" }
    static func clearHistoryMessage(_ l: AppLanguage) -> String {
        l == .chinese
            ? "确定要清除所有下载历史吗？此操作不可撤销。"
            : "Are you sure you want to clear all download history? This cannot be undone."
    }

    // MARK: Notification localized (#11)

    static func notificationTitle(_ l: AppLanguage) -> String { l == .chinese ? "下载完成" : "Download Complete" }
    static func notificationBody(_ l: AppLanguage) -> String { l == .chinese ? "文件已保存" : "File saved successfully" }

    // MARK: Paste URL (#13)

    static func pasteURLHelp(_ l: AppLanguage) -> String { l == .chinese ? "从剪贴板粘贴 URL" : "Paste URL from clipboard" }
}
