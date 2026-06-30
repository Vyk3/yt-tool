import Foundation

// MARK: - Language enum

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh-Hans"

    var id: String {
        rawValue
    }

    /// Foundation Locale matching this language, for SwiftUI `.environment(\.locale, ...)`.
    var locale: Locale {
        Locale(identifier: rawValue)
    }

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

    static func history(_ l: AppLanguage) -> String {
        l == .chinese ? "历史" : "History"
    }

    static func cancel(_ l: AppLanguage) -> String {
        l == .chinese ? "取消" : "Cancel"
    }

    // MARK: Subscriptions view

    static func channelURLPlaceholder(_ l: AppLanguage) -> String {
        l == .chinese ? "YouTube / bilibili 频道或视频 URL" : "YouTube / bilibili channel or video URL"
    }

    static func subscribe(_ l: AppLanguage) -> String {
        l == .chinese ? "订阅" : "Subscribe"
    }

    static func newVideos(_ l: AppLanguage) -> String {
        l == .chinese ? "新视频" : "New Videos"
    }

    static func dismissAll(_ l: AppLanguage) -> String {
        l == .chinese ? "全部忽略" : "Dismiss All"
    }

    static func channels(_ l: AppLanguage) -> String {
        l == .chinese ? "频道" : "Channels"
    }

    static func checkNow(_ l: AppLanguage) -> String {
        l == .chinese ? "立即检查" : "Check Now"
    }

    static func selectAction(_ l: AppLanguage) -> String {
        l == .chinese ? "选择" : "Select"
    }

    static func done(_ l: AppLanguage) -> String {
        l == .chinese ? "完成" : "Done"
    }

    static func deleteLabel(_ l: AppLanguage) -> String {
        l == .chinese ? "删除" : "Delete"
    }

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

    static func copyAllURLs(_ l: AppLanguage) -> String {
        l == .chinese ? "复制全部链接" : "Copy All URLs"
    }

    static func copyURLHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "复制视频链接" : "Copy video URL"
    }

    static func checkedPrefix(_ l: AppLanguage) -> String {
        l == .chinese ? "已检查 · " : "Checked "
    }

    static func checkedSuffix(_ l: AppLanguage) -> String {
        l == .chinese ? "" : " ago"
    }

    // MARK: Settings sections

    static func sectionDownload(_ l: AppLanguage) -> String {
        l == .chinese ? "下载" : "Download"
    }

    static func sectionSubscriptions(_ l: AppLanguage) -> String {
        l == .chinese ? "订阅" : "Subscriptions"
    }

    static func sectionUpdates(_ l: AppLanguage) -> String {
        l == .chinese ? "更新" : "Updates"
    }

    static let sectionYtDlp = "yt-dlp"

    /// Poll interval labels
    static func interval15min(_ l: AppLanguage) -> String {
        l == .chinese ? "15 分钟" : "15 min"
    }

    static func interval30min(_ l: AppLanguage) -> String {
        l == .chinese ? "30 分钟" : "30 min"
    }

    static func interval1hour(_ l: AppLanguage) -> String {
        l == .chinese ? "1 小时" : "1 hour"
    }

    static func interval2hours(_ l: AppLanguage) -> String {
        l == .chinese ? "2 小时" : "2 hours"
    }

    static func sectionAppUpdates(_ l: AppLanguage) -> String {
        l == .chinese ? "应用更新" : "App Updates"
    }

    static func sectionAbout(_ l: AppLanguage) -> String {
        l == .chinese ? "关于" : "About"
    }

    static func sectionPrivacy(_ l: AppLanguage) -> String {
        l == .chinese ? "隐私" : "Privacy"
    }

    static func sectionLanguage(_ l: AppLanguage) -> String {
        l == .chinese ? "显示" : "Display"
    }

    // MARK: Settings rows

    static func downloadEngine(_ l: AppLanguage) -> String {
        l == .chinese ? "下载引擎" : "Download engine"
    }

    static func aria2cNotFound(_ l: AppLanguage) -> String {
        l == .chinese
            ? "未找到 aria2c — 可通过 brew install aria2 安装"
            : "aria2c not found — install via: brew install aria2"
    }

    static func cookiesFile(_ l: AppLanguage) -> String {
        l == .chinese ? "Cookies 文件" : "Cookies file"
    }

    static func cookiesDescription(_ l: AppLanguage) -> String {
        l == .chinese
            ? "可选。用于下载需要登录的内容（如更高画质、年龄限制、会员视频）。"
            : "Optional. For content that requires login (e.g. higher quality, age-restricted, member-only)."
    }

    static func cookiesGuideTitle(_ l: AppLanguage) -> String {
        l == .chinese ? "Cookies 使用指南" : "Cookies Guide"
    }

    static func cookiesGuideIntro(_ l: AppLanguage) -> String {
        l == .chinese
            ? "部分内容需要登录才能下载（如更高画质、年龄限制、会员视频）。"
            : "Some content requires login to download (e.g. higher quality, age-restricted, member-only)."
    }

    static func cookiesGuideStepTitles(_ l: AppLanguage) -> [String] {
        if l == .chinese {
            return ["安装浏览器扩展", "导出 Cookies", "填写路径"]
        }
        return ["Install browser extension", "Export cookies", "Paste the path"]
    }

    static func cookiesGuideStepDetails(_ l: AppLanguage) -> [String] {
        if l == .chinese {
            return [
                "在扩展商店搜索并安装 Get cookies.txt LOCALLY（免费、开源）",
                "打开视频网站 → 确认已登录 → 点击扩展图标 → 导出并保存文件",
                "将文件的完整路径粘贴到左边输入框（如 ~/Downloads/cookies.txt）",
            ]
        }
        return [
            "Install Get cookies.txt LOCALLY from your extension store (free, open-source)",
            "Open the video site → log in → click the extension icon → export and save",
            "Paste the full file path into the input field (e.g. ~/Downloads/cookies.txt)",
        ]
    }

    static func cookiesGuideWarning(_ l: AppLanguage) -> String {
        l == .chinese
            ? "⚠️ cookies.txt 包含登录信息，用完建议删除，请勿分享。"
            : "⚠️ cookies.txt contains login info — delete after use, never share."
    }

    static func cookiesGuideLink(_ l: AppLanguage) -> String {
        l == .chinese ? "如何获取？" : "How to get one?"
    }

    static func cookiesGuideAdvanced(_ l: AppLanguage) -> String {
        l == .chinese
            ? "进阶：使用浏览器扩展导出 cookies.txt 文件，然后在上方指定路径。"
            : "Advanced: export a cookies.txt file using a browser extension, then specify its path above."
    }

    // MARK: Privacy

    static func privacyTitle(_ l: AppLanguage) -> String {
        l == .chinese ? "隐私说明" : "Privacy"
    }

    static func privacyPoints(_ l: AppLanguage) -> [String] {
        if l == .chinese {
            return [
                "YTTool 不包含任何数据分析、使用统计或广告追踪功能。",
                "不会向 YTTool 开发者或任何第三方发送你的个人数据。",
                "App 仅与视频平台（如 YouTube）和 GitHub（检查更新）通信，不连接其他服务。",
                "Cookies 文件仅由 yt-dlp 在本机读取，YTTool 不会解析、缓存或传输其内容。",
                "下载历史和偏好设置仅保存在本机，可随时清除。",
            ]
        }
        return [
            "YTTool contains no analytics, telemetry, or ad tracking.",
            "No personal data is ever sent to YTTool's developers or any third party.",
            "The app only communicates with video platforms (e.g. YouTube) and GitHub (for update checks) — no other services.",
            "Cookie files are read only by yt-dlp locally — YTTool never parses, caches, or transmits their contents.",
            "Download history and preferences are stored locally and can be cleared at any time.",
        ]
    }

    static func clearLocalData(_ l: AppLanguage) -> String {
        l == .chinese ? "清除本地数据" : "Clear local data"
    }

    static func clearLocalDataHelp(_ l: AppLanguage) -> String {
        l == .chinese
            ? "删除本机偏好、历史、订阅、新视频缓存和本地 yt-dlp；不会删除下载文件或 cookies 文件。"
            : "Deletes local preferences, history, subscriptions, new-video cache, and user-local yt-dlp. Downloads and cookies files are not touched."
    }

    static func clearLocalDataConfirmTitle(_ l: AppLanguage) -> String {
        l == .chinese ? "清除本地数据？" : "Clear local data?"
    }

    static func clearLocalDataConfirmMessage(_ l: AppLanguage) -> String {
        l == .chinese
            ? "会先创建备份，然后删除 YTTool 的本机元数据。下载文件和 cookies 文件不会被删除。"
            : "A backup is created first, then YTTool's local metadata is deleted. Downloads and cookies files are not deleted."
    }

    static func extraArgs(_ l: AppLanguage) -> String {
        l == .chinese ? "额外 yt-dlp 参数" : "Extra yt-dlp arguments"
    }

    static func extraArgsDescription(_ l: AppLanguage) -> String {
        l == .chinese
            ? "可选。仅支持 --limit-rate、--proxy 等特定参数，如 --limit-rate 5M"
            : "Optional. Only specific options are allowed, e.g. --limit-rate 5M"
    }

    static func checkInterval(_ l: AppLanguage) -> String {
        l == .chinese ? "检查间隔" : "Check interval"
    }

    static func checkIntervalDescription(_ l: AppLanguage) -> String {
        l == .chinese ? "轮询订阅频道新视频的频率。" : "How often to poll subscribed channels for new uploads."
    }

    static func automaticChecks(_ l: AppLanguage) -> String {
        l == .chinese ? "自动检查" : "Automatic checks"
    }

    static func automaticChecksDescription(_ l: AppLanguage) -> String {
        l == .chinese ? "启动时检查应用更新。" : "Check for app updates on launch."
    }

    static func checkForAppUpdates(_ l: AppLanguage) -> String {
        l == .chinese ? "检查应用更新" : "Check for App Updates"
    }

    static func ytDlpDependency(_ l: AppLanguage) -> String {
        l == .chinese ? "依赖：yt-dlp" : "Dependency: yt-dlp"
    }

    static func ytDlpDescription(_ l: AppLanguage) -> String {
        l == .chinese ? "第三方视频下载引擎" : "Third-party video download engine"
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

    static func appUpdateLabel(_ l: AppLanguage) -> String {
        l == .chinese ? "应用更新" : "App update"
    }

    static func appVersionLabel(_ l: AppLanguage) -> String {
        l == .chinese ? "应用版本" : "App version"
    }

    static func buildLabel(_ l: AppLanguage) -> String {
        l == .chinese ? "构建号" : "Build"
    }

    static func repositoryLink(_ l: AppLanguage) -> String {
        l == .chinese ? "仓库" : "Repository"
    }

    static func languageLabel(_ l: AppLanguage) -> String {
        l == .chinese ? "语言" : "Language"
    }

    static func languageDescription(_ l: AppLanguage) -> String {
        l == .chinese ? "切换界面显示语言。" : "Switch the display language."
    }

    static func appearanceLabel(_ l: AppLanguage) -> String {
        l == .chinese ? "外观" : "Appearance"
    }

    static func technicalDetails(_ l: AppLanguage) -> String {
        l == .chinese ? "技术详情" : "Technical details"
    }

    static func technicalDetailsHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "在格式列表中显示 ID、编码、FPS、码率等详细列" : "Show ID, codec, FPS, bitrate columns in format lists"
    }

    static func showAllFormats(_ l: AppLanguage) -> String {
        l == .chinese ? "显示全部格式" : "Show all formats"
    }

    static func showAllFormatsHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "关闭时每个分辨率只显示最佳格式，不影响探测速度" : "When off, show only the best format per resolution. Does not affect probe speed"
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

    static func currentVersionLabel(_ l: AppLanguage) -> String {
        l == .chinese ? "当前版本" : "Current version"
    }

    static func channelLabel(_ l: AppLanguage) -> String {
        l == .chinese ? "更新通道" : "Channel"
    }

    static func autoCheckYtDlp(_ l: AppLanguage) -> String {
        l == .chinese ? "启动时检查 yt-dlp 更新" : "Auto-check yt-dlp updates"
    }

    static func checkForUpdates(_ l: AppLanguage) -> String {
        l == .chinese ? "检查更新" : "Check for Updates"
    }

    static func checking(_ l: AppLanguage) -> String {
        l == .chinese ? "检查中…" : "Checking..."
    }

    static func updateAvailable(_ current: String, _ latest: String, _ l: AppLanguage) -> String {
        l == .chinese ? "有可用更新：\(current) → \(latest)" : "Update available: \(current) → \(latest)"
    }

    static func installUpdate(_ l: AppLanguage) -> String {
        l == .chinese ? "安装更新" : "Install Update"
    }

    static func upToDate(_ version: String, _ l: AppLanguage) -> String {
        l == .chinese ? "已是最新 (\(version))" : "Up to date (\(version))"
    }

    static func checkAgain(_ l: AppLanguage) -> String {
        l == .chinese ? "再次检查" : "Check Again"
    }

    static func downloadingUpdate(_ l: AppLanguage) -> String {
        l == .chinese ? "下载中…" : "Downloading..."
    }

    static func verifyingInstalling(_ l: AppLanguage) -> String {
        l == .chinese ? "验证并安装中…" : "Verifying and installing..."
    }

    static func updatedTo(_ version: String, _ l: AppLanguage) -> String {
        l == .chinese ? "已更新至 \(version)" : "Updated to \(version)"
    }

    static func retry(_ l: AppLanguage) -> String {
        l == .chinese ? "重试" : "Retry"
    }

    // MARK: URL input view

    static func urlHeading(_: AppLanguage) -> String {
        "URL"
    }

    static func dragHint(_ l: AppLanguage) -> String {
        l == .chinese ? "你也可以将视频 URL 拖放到输入框中。" : "You can also drag a video URL into the field."
    }

    static func probeButton(_ l: AppLanguage) -> String {
        l == .chinese ? "探测" : "Probe"
    }

    static func probeFirstItem(_ l: AppLanguage) -> String {
        l == .chinese ? "探测第一个" : "Probe first item"
    }

    static func statusIdle(_ l: AppLanguage) -> String {
        l == .chinese ? "空闲" : "Idle"
    }

    static func statusProbing(_ l: AppLanguage) -> String {
        l == .chinese ? "探测中…" : "Probing…"
    }

    static func statusReady(_ title: String, _ l: AppLanguage) -> String {
        l == .chinese ? "就绪：\(title)" : "Ready: \(title)"
    }

    static func statusProbeFailed(_ detail: String?, _ l: AppLanguage) -> String {
        let prefix = l == .chinese ? "探测失败。" : "yt-dlp probe failed."
        if let detail, !detail.isEmpty { return "\(prefix) \(detail)" }
        return prefix
    }

    static func chooseFolderHint(_ l: AppLanguage) -> String {
        l == .chinese ? "选择文件夹…" : "Choose folder…"
    }

    static func clearFolderHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "清除所选文件夹" : "Clear selected folder"
    }

    /// Playlist mode
    static func playlistMode(_ l: AppLanguage) -> String {
        l == .chinese ? "播放列表模式" : "Playlist mode"
    }

    static func playlistModeHintFirst(_ l: AppLanguage) -> String {
        l == .chinese ? "仅探测第一个项目，然后像单个视频一样下载。" : "Probe inspects only the first item, then downloads it like a single video."
    }

    static func playlistModeHintWhole(_ l: AppLanguage) -> String {
        l == .chinese ? "整个播放列表会自动下载所有项目。" : "Whole playlist downloads every item automatically."
    }

    static func videoQuality(_ l: AppLanguage) -> String {
        l == .chinese ? "视频质量" : "Video quality"
    }

    static func videoQualityHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "整个播放列表下载时，优先兼容性还是更高画质。" : "Choose whether whole-playlist video downloads favor compatibility or higher quality."
    }

    static func audioQuality(_ l: AppLanguage) -> String {
        l == .chinese ? "音频质量" : "Audio quality"
    }

    static func audioQualityHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "整个播放列表下载时，优先兼容性还是更高音质。" : "Choose whether whole-playlist audio downloads favor compatibility or higher quality."
    }

    static func playlistFormats(_ l: AppLanguage) -> String {
        l == .chinese ? "播放列表格式" : "Playlist formats"
    }

    static func playlistFormatsHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "使用统一策略下载所有项目，或为特定项目指定格式。" : "Use a single strategy for all items, or map specific items to specific format selectors."
    }

    static func perItemMap(_ l: AppLanguage) -> String {
        l == .chinese ? "逐项映射" : "Per-item map"
    }

    static func perItemMapHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "为列表中的特定视频指定格式，如 1=best;3=worst。" : "Assign formats to specific items, e.g. 1=best;3=worst."
    }

    static func perItemMapEmptySummary(_ l: AppLanguage) -> String {
        l == .chinese ? "尚未配置逐项格式。" : "No per-item formats configured yet."
    }

    static func perItemMapConfiguredSummary(_ count: Int, _ l: AppLanguage) -> String {
        l == .chinese ? "已配置 \(count) 项格式。" : "\(count) item formats configured."
    }

    static func advancedPerItemMap(_ l: AppLanguage) -> String {
        l == .chinese ? "高级：手动编辑映射" : "Advanced: edit raw map"
    }

    static func playlistSubtitles(_ l: AppLanguage) -> String {
        l == .chinese ? "播放列表字幕" : "Playlist subtitles"
    }

    static func playlistSubtitlesHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "为播放列表中的每个项目应用相同的字幕策略。" : "Apply the same subtitle strategy to each item in the playlist."
    }

    static func subtitleLanguageLabel(_ l: AppLanguage) -> String {
        l == .chinese ? "字幕语言" : "Subtitle language"
    }

    static func subtitleLanguageHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "整个播放列表下载时使用的字幕语言。" : "Subtitle language used for whole-playlist downloads."
    }

    static func playlistSegments(_ l: AppLanguage) -> String {
        l == .chinese ? "播放列表片段" : "Playlist segments"
    }

    static func playlistSegmentsHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "选择每个项目是完整下载还是指定时间范围。" : "Choose whether each item downloads fully or with a fixed time range."
    }

    static func timeRange(_ l: AppLanguage) -> String {
        l == .chinese ? "时间范围" : "Time range"
    }

    static func timeRangeHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "指定每个视频的下载时间段，如 00:01:00-00:02:00。" : "Specify a time range for each video, e.g. 00:01:00-00:02:00."
    }

    // MARK: Format picker view

    static func formatsHeading(_ l: AppLanguage) -> String {
        l == .chinese ? "格式" : "Formats"
    }

    static func videoLabel(_ l: AppLanguage) -> String {
        l == .chinese ? "视频" : "Video"
    }

    static func audioLabel(_ l: AppLanguage) -> String {
        l == .chinese ? "音频" : "Audio"
    }

    static func subtitlesLabel(_ l: AppLanguage) -> String {
        l == .chinese ? "字幕" : "Subtitles"
    }

    static func manualSubs(_ l: AppLanguage) -> String {
        l == .chinese ? "手动" : "Manual"
    }

    static func autoSubs(_ l: AppLanguage) -> String {
        l == .chinese ? "自动生成" : "Auto-generated"
    }

    static func loadingFormats(_ l: AppLanguage) -> String {
        l == .chinese ? "加载格式中…" : "Loading formats…"
    }

    static func probeToInspect(_ l: AppLanguage) -> String {
        l == .chinese ? "探测 URL 以查看可用格式。" : "Probe a URL to inspect available formats."
    }

    static func viewCount(_ compactCount: String, _ l: AppLanguage) -> String {
        l == .chinese ? "\(compactCount) 次观看" : "\(compactCount) views"
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

    static func noVideoFormats(_ l: AppLanguage) -> String {
        l == .chinese ? "未检测到视频格式。" : "No video formats detected."
    }

    static func noAudioFormats(_ l: AppLanguage) -> String {
        l == .chinese ? "未检测到音频格式。" : "No audio formats detected."
    }

    // MARK: Download progress view

    static func downloadHeading(_ l: AppLanguage) -> String {
        l == .chinese ? "下载" : "Download"
    }

    static func cancelButton(_ l: AppLanguage) -> String {
        l == .chinese ? "取消" : "Cancel"
    }

    static func downloadButton(_ l: AppLanguage) -> String {
        l == .chinese ? "下载" : "Download"
    }

    static func readyToDownload(_ l: AppLanguage) -> String {
        l == .chinese ? "准备就绪。点按「下载」开始。" : "Ready to download. Press Download to start."
    }

    static func selectFormatHint(_ l: AppLanguage) -> String {
        l == .chinese ? "选择格式和输出文件夹以启用下载。" : "Select a format and output folder to enable download."
    }

    static func noFormatsCanDownload(_ l: AppLanguage) -> String {
        l == .chinese
            ? "未检测到可选格式，将自动选择最佳质量下载。"
            : "No selectable formats found; will download at best available quality."
    }

    static func noFormatsNeedFolder(_ l: AppLanguage) -> String {
        l == .chinese
            ? "未显示可选格式。请先选择输出文件夹；若已选择，请重试探测或查看日志。"
            : "No selectable formats. Select an output folder first; if already selected, retry Probe or check logs."
    }

    static func stagePreparing(_ l: AppLanguage) -> String {
        l == .chinese ? "准备中" : "Preparing"
    }

    static func stagePreparingSub(_ l: AppLanguage) -> String {
        l == .chinese ? "正在构建 yt-dlp 命令并启动进程。" : "Building the yt-dlp command and starting the process."
    }

    static func stageDownloading(_ l: AppLanguage) -> String {
        l == .chinese ? "下载中" : "Downloading"
    }

    static func stageDownloadingSub(_ l: AppLanguage) -> String {
        l == .chinese ? "传输正在进行中。" : "The active transfer is in progress."
    }

    static func stageCompleted(_ l: AppLanguage) -> String {
        l == .chinese ? "完成 ✓" : "Completed ✓"
    }

    static func stageCompletedSubFile(_ l: AppLanguage) -> String {
        l == .chinese ? "选择对下载文件的操作。" : "Choose what to do with the finished file."
    }

    static func stageCompletedSubDir(_ l: AppLanguage) -> String {
        l == .chinese ? "选择对下载项目的操作。" : "Choose what to do with the downloaded items."
    }

    static func stageFailed(_ l: AppLanguage) -> String {
        l == .chinese ? "失败" : "Failed"
    }

    static func stageFailedSub(_ l: AppLanguage) -> String {
        l == .chinese ? "下载在完成前中断。" : "The download stopped before completion."
    }

    static func stageCancelled(_ l: AppLanguage) -> String {
        l == .chinese ? "已取消" : "Cancelled"
    }

    static func stageCancelledSub(_ l: AppLanguage) -> String {
        l == .chinese ? "下载已停止。" : "The download was stopped."
    }

    static func cancelledHint(_ l: AppLanguage) -> String {
        l == .chinese ? "你可以调整格式或输出文件夹，然后开始新的下载。" : "You can adjust the format or output folder, then start a new download."
    }

    static func revealInFinder(_ l: AppLanguage) -> String {
        l == .chinese ? "在 Finder 中显示" : "Reveal in Finder"
    }

    static func openFolder(_ l: AppLanguage) -> String {
        l == .chinese ? "打开文件夹" : "Open Folder"
    }

    static func copyFilePath(_ l: AppLanguage) -> String {
        l == .chinese ? "复制文件路径" : "Copy File Path"
    }

    static func copyFolderPath(_ l: AppLanguage) -> String {
        l == .chinese ? "复制文件夹路径" : "Copy Folder Path"
    }

    static func newDownload(_ l: AppLanguage) -> String {
        l == .chinese ? "新的下载" : "New Download"
    }

    static func reasonLabel(_ l: AppLanguage) -> String {
        l == .chinese ? "原因" : "Reason"
    }

    static func tryThisLabel(_ l: AppLanguage) -> String {
        l == .chinese ? "建议" : "Try this"
    }

    static func ffmpegUnavailable(_ l: AppLanguage) -> String {
        l == .chinese ? "FFmpeg 不可用" : "FFmpeg unavailable"
    }

    static func sizeLabel(_ l: AppLanguage) -> String {
        l == .chinese ? "大小" : "Size"
    }

    static func speedLabel(_ l: AppLanguage) -> String {
        l == .chinese ? "速度" : "Speed"
    }

    // MARK: Advanced options view

    static func advancedOptions(_ l: AppLanguage) -> String {
        l == .chinese ? "高级选项（可选）" : "Advanced options (optional)"
    }

    static func audioTranscode(_ l: AppLanguage) -> String {
        l == .chinese ? "音频转码" : "Audio transcode"
    }

    static func cookiesSet(_ l: AppLanguage) -> String {
        l == .chinese ? "Cookies 已设置" : "Cookies set"
    }

    static func extraArgsSet(_ l: AppLanguage) -> String {
        l == .chinese ? "额外参数已设置" : "Extra args set"
    }

    static func changeInSettings(_ l: AppLanguage) -> String {
        l == .chinese ? "在设置标签页中修改" : "Change in Settings tab"
    }

    // MARK: Log panel view

    static func sessionLog(_ l: AppLanguage) -> String {
        l == .chinese ? "会话日志" : "Session Log"
    }

    static func nEntries(_ n: Int, _ l: AppLanguage) -> String {
        l == .chinese ? "\(n) 条" : "\(n) entries"
    }

    static func showLogs(_ l: AppLanguage) -> String {
        l == .chinese ? "展开日志" : "Show Logs"
    }

    static func hideLogs(_ l: AppLanguage) -> String {
        l == .chinese ? "收起日志" : "Hide Logs"
    }

    static func latestActivity(_ l: AppLanguage) -> String {
        l == .chinese ? "最近活动" : "Latest activity"
    }

    static func logPlaceholder(_ l: AppLanguage) -> String {
        l == .chinese ? "探测和下载事件将在此会话期间显示在这里。" : "Probe and download events will appear here during this app session."
    }

    // MARK: History view

    static func downloadHistory(_ l: AppLanguage) -> String {
        l == .chinese ? "下载历史" : "Download History"
    }

    static func clearAll(_ l: AppLanguage) -> String {
        l == .chinese ? "全部清除" : "Clear All"
    }

    static func noDownloadsYet(_ l: AppLanguage) -> String {
        l == .chinese ? "暂无下载记录。" : "No downloads yet."
    }

    static func reveal(_ l: AppLanguage) -> String {
        l == .chinese ? "显示" : "Reveal"
    }

    // MARK: Queue view (ContentView inline)

    static func urlsPerLine(_ l: AppLanguage) -> String {
        l == .chinese ? "URL（每行一个）" : "URLs (one per line)"
    }

    static func queueURLPlaceholder(_ l: AppLanguage) -> String {
        l == .chinese
            ? "https://www.youtube.com/watch?v=...\nhttps://www.bilibili.com/video/..."
            : "https://www.youtube.com/watch?v=...\nhttps://www.bilibili.com/video/..."
    }

    static func importButton(_ l: AppLanguage) -> String {
        l == .chinese ? "导入" : "Import"
    }

    static func pasteButton(_ l: AppLanguage) -> String {
        l == .chinese ? "粘贴" : "Paste"
    }

    static func addToQueue(_ l: AppLanguage) -> String {
        l == .chinese ? "添加到队列" : "Add to Queue"
    }

    static func estimated(_ total: String, _ detail: String, _ l: AppLanguage) -> String {
        l == .chinese ? "预估：\(total)\(detail)" : "Estimated: \(total)\(detail)"
    }

    // MARK: Queue view (QueueView + QueueItemRow)

    static func queueCount(_ n: Int, _ l: AppLanguage) -> String {
        l == .chinese ? "队列（\(n) 项）" : "Queue (\(n) items)"
    }

    static func queueStop(_ l: AppLanguage) -> String {
        l == .chinese ? "停止" : "Stop"
    }

    static func queueStart(_ l: AppLanguage) -> String {
        l == .chinese ? "开始" : "Start"
    }

    static func queueClearDone(_ l: AppLanguage) -> String {
        l == .chinese ? "清除已完成" : "Clear done"
    }

    static func queueEmpty(_ l: AppLanguage) -> String {
        l == .chinese
            ? "队列为空。在上方粘贴 URL 并点击「添加到队列」。"
            : "No items in queue. Paste URLs above and click Add to Queue."
    }

    static func queuePending(_ l: AppLanguage) -> String {
        l == .chinese ? "等待中" : "Pending"
    }

    static func queueStarting(_ l: AppLanguage) -> String {
        l == .chinese ? "启动中…" : "Starting..."
    }

    static func queueCompleted(_ l: AppLanguage) -> String {
        l == .chinese ? "已完成" : "Completed"
    }

    static func queueItemFailed(_ l: AppLanguage) -> String {
        l == .chinese ? "失败" : "Failed"
    }

    static func queueItemCancelled(_ l: AppLanguage) -> String {
        l == .chinese ? "已取消" : "Cancelled"
    }

    static func queueRemoveHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "从队列中移除" : "Remove from queue"
    }

    static func queueCancelHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "取消下载" : "Cancel download"
    }

    static func queueRetryHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "重试" : "Retry"
    }

    static func queueNeedFolder(_ l: AppLanguage) -> String {
        l == .chinese ? "请先选择输出文件夹再添加到队列。" : "Select an output folder before adding to queue."
    }

    static func queueUnsupportedURLs(_ count: Int, _ l: AppLanguage) -> String {
        if l == .chinese {
            count == 1
                ? "1 个链接不属于已知视频平台，已跳过。"
                : "\(count) 个链接不属于已知视频平台，已跳过。"
        } else {
            count == 1
                ? "1 URL is not from a supported video platform and was skipped."
                : "\(count) URLs are not from supported video platforms and were skipped."
        }
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

    /// Queue quality strategy
    static func qualityBest(_ l: AppLanguage) -> String {
        l == .chinese ? "最佳质量" : "Best quality"
    }

    static func qualityMax1080(_ l: AppLanguage) -> String {
        l == .chinese ? "最高 1080p" : "1080p max"
    }

    static func qualityMax720(_ l: AppLanguage) -> String {
        l == .chinese ? "最高 720p" : "720p max"
    }

    static func qualityAudioOnly(_ l: AppLanguage) -> String {
        l == .chinese ? "仅音频" : "Audio only"
    }

    static func qualityLabel(_ l: AppLanguage) -> String {
        l == .chinese ? "质量" : "Quality"
    }

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
            case "ultralow": "极低"
            case "low": "基础"
            case "medium": "标准"
            case "high": "高"
            default: note
            }
        } else {
            switch note.lowercased() {
            case "ultralow": "Minimal"
            case "low": "Basic"
            case "medium": "Standard"
            case "high": "High"
            default: note
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

    static func retryDownload(_ l: AppLanguage) -> String {
        l == .chinese ? "重新下载" : "Retry Download"
    }

    // MARK: Precise download disabled reason (#3)

    static func needFolderHint(_ l: AppLanguage) -> String {
        l == .chinese ? "请选择输出文件夹以启用下载。" : "Select an output folder to enable download."
    }

    static func needFormatHint(_ l: AppLanguage) -> String {
        l == .chinese ? "请选择至少一个格式以启用下载。" : "Select at least one format to enable download."
    }

    // MARK: Add video to queue from subscriptions (#4)

    static func addVideoToQueue(_ l: AppLanguage) -> String {
        l == .chinese ? "加入队列" : "Add to Queue"
    }

    static func subsUnsupportedPlatform(_ l: AppLanguage) -> String {
        l == .chinese ? "仅支持 YouTube 和 bilibili 链接" : "Only YouTube and bilibili URLs are supported"
    }

    static func addedToQueueInput(_ l: AppLanguage) -> String {
        l == .chinese ? "已加入下载队列" : "Added to download queue"
    }

    // MARK: Playlist enum titles

    static func playlistModeTitle(_ mode: PlaylistMode, _ l: AppLanguage) -> String {
        mode.title(l)
    }

    static func playlistVideoQualityTitle(_ s: PlaylistVideoQualityStrategy, _ l: AppLanguage) -> String {
        s.title(l)
    }

    static func playlistAudioQualityTitle(_ s: PlaylistAudioQualityStrategy, _ l: AppLanguage) -> String {
        s.title(l)
    }

    static func playlistSubtitleModeTitle(_ mode: PlaylistSubtitleMode, _ l: AppLanguage) -> String {
        mode.title(l)
    }

    static func playlistSegmentModeTitle(_ mode: PlaylistSegmentMode, _ l: AppLanguage) -> String {
        mode.title(l)
    }

    static func playlistFormatModeTitle(_ mode: PlaylistFormatMode, _ l: AppLanguage) -> String {
        mode.title(l)
    }

    // MARK: Playlist format editor

    static func configureFormatMap(_ l: AppLanguage) -> String {
        l == .chinese ? "选择每项格式…" : "Choose formats per item…"
    }

    static func formatEditorTitle(_ l: AppLanguage) -> String {
        l == .chinese ? "逐项格式选择" : "Per-Item Format Selection"
    }

    static func formatEditorLoading(_ l: AppLanguage) -> String {
        l == .chinese ? "正在加载播放列表…" : "Loading playlist…"
    }

    static func formatEditorProbed(_ probed: Int, _ total: Int, _ l: AppLanguage) -> String {
        l == .chinese ? "已探测 \(probed)/\(total)" : "\(probed)/\(total) probed"
    }

    static func formatEditorSelectAll(_ l: AppLanguage) -> String {
        l == .chinese ? "全选" : "Select All"
    }

    static func formatEditorDeselectAll(_ l: AppLanguage) -> String {
        l == .chinese ? "取消全选" : "Deselect All"
    }

    static func formatEditorProbeSelected(_ l: AppLanguage) -> String {
        l == .chinese ? "探测选中项" : "Probe Selected"
    }

    static func formatEditorProbing(_ l: AppLanguage) -> String {
        l == .chinese ? "探测中…" : "Probing…"
    }

    static func formatEditorRetry(_ l: AppLanguage) -> String {
        l == .chinese ? "重试" : "Retry"
    }

    static func formatEditorConfirm(_ l: AppLanguage) -> String {
        l == .chinese ? "确认" : "Confirm"
    }

    static func formatEditorCancel(_ l: AppLanguage) -> String {
        l == .chinese ? "取消" : "Cancel"
    }

    static func formatEditorAutoFormat(_ l: AppLanguage) -> String {
        l == .chinese ? "自动" : "Auto"
    }

    static func formatEditorVideo(_ l: AppLanguage) -> String {
        l == .chinese ? "视频" : "Video"
    }

    static func formatEditorAudio(_ l: AppLanguage) -> String {
        l == .chinese ? "音频" : "Audio"
    }

    static func formatEditorManualInput(_ l: AppLanguage) -> String {
        l == .chinese ? "手动输入格式" : "Manual format input"
    }

    static func formatEditorEmpty(_ l: AppLanguage) -> String {
        l == .chinese ? "播放列表为空或无法加载。" : "Playlist is empty or could not be loaded."
    }

    // MARK: Format picker column headers (#6)

    static func colRes(_ l: AppLanguage) -> String {
        l == .chinese ? "分辨率" : "Res"
    }

    static func colCodec(_ l: AppLanguage) -> String {
        l == .chinese ? "编码" : "Codec"
    }

    static func colBitrate(_ l: AppLanguage) -> String {
        l == .chinese ? "码率" : "Bitrate"
    }

    static func colSize(_ l: AppLanguage) -> String {
        l == .chinese ? "大小" : "Size"
    }

    static func colNote(_ l: AppLanguage) -> String {
        l == .chinese ? "备注" : "Note"
    }

    static func colProtocol(_ l: AppLanguage) -> String {
        l == .chinese ? "协议" : "Proto"
    }

    // MARK: Log error badge (#8)

    static func errorBadge(_ n: Int, _ l: AppLanguage) -> String {
        l == .chinese ? "\(n) 个错误" : "\(n) error\(n == 1 ? "" : "s")"
    }

    // MARK: History clear confirmation (#9)

    static func clearHistoryTitle(_ l: AppLanguage) -> String {
        l == .chinese ? "确认清除" : "Clear History"
    }

    static func clearHistoryMessage(_ l: AppLanguage) -> String {
        l == .chinese
            ? "确定要清除所有下载历史吗？此操作不可撤销。"
            : "Are you sure you want to clear all download history? This cannot be undone."
    }

    // MARK: Notification localized (#11)

    static func notificationTitle(_ l: AppLanguage) -> String {
        l == .chinese ? "下载完成" : "Download Complete"
    }

    static func notificationBody(_ l: AppLanguage) -> String {
        l == .chinese ? "文件已保存" : "File saved successfully"
    }

    // MARK: Cookie expiry (#84)

    static func cookieExpiredMessage(_ l: AppLanguage) -> String {
        l == .chinese
            ? "Cookies 可能已过期或失效。"
            : "Cookies may be expired or invalid."
    }

    static func cookieExpiredSuggestion(_ l: AppLanguage) -> String {
        l == .chinese
            ? "请重新导出 cookies 文件并更新路径，然后重试。"
            : "Re-export your cookies file, update the path, and try again."
    }

    static func needsCookiesMessage(_ l: AppLanguage) -> String {
        l == .chinese
            ? "Bilibili 需要 Cookies 才能访问该内容。"
            : "Bilibili needs cookies to access this content."
    }

    static func needsCookiesSuggestion(_ l: AppLanguage) -> String {
        let label = cookiesFile(l)
        return l == .chinese
            ? "请在设置中添加 \(label) 路径，然后重试。"
            : "Add a \(label) path in Settings, then try again."
    }

    // MARK: Paste URL (#13)

    static func pasteURLHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "从剪贴板粘贴 URL" : "Paste URL from clipboard"
    }

    // MARK: Misc UI labels

    static func etaLabel(_ l: AppLanguage) -> String {
        l == .chinese ? "剩余" : "ETA"
    }

    static func ffmpegMissingHelp(_ l: AppLanguage) -> String {
        l == .chinese ? "ffmpeg 或 ffprobe 缺失。" : "ffmpeg or ffprobe is missing."
    }

    static func selectFolder(_ l: AppLanguage) -> String {
        l == .chinese ? "选择" : "Select"
    }
}
