import AppKit
import Foundation
import UserNotifications

enum AppMode: String, CaseIterable, Identifiable {
    case single
    case queue
    case subscriptions
    case settings

    var id: String {
        rawValue
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String {
        rawValue
    }
}

@MainActor
final class AppState: ObservableObject {
    private enum StorageKey {
        static let selectedOutputDirectoryPath = "selectedOutputDirectoryPath"
        static let downloaderPreference = "downloaderPreference"
        static let updateChannel = "updateChannel"
        static let autoCheckForUpdates = "autoCheckForUpdates"
        static let autoCheckForAppUpdates = "autoCheckForAppUpdates"
        static let appLanguage = "appLanguage"
        static let appAppearance = "appAppearance"
        static let showTechnicalDetails = "showTechnicalDetails"
        static let showAllFormats = "showAllFormats"

        static let localDataKeys = [
            selectedOutputDirectoryPath,
            downloaderPreference,
            updateChannel,
            autoCheckForUpdates,
            autoCheckForAppUpdates,
            appLanguage,
            appAppearance,
            showTechnicalDetails,
            showAllFormats,
            "AppleLanguages",
            "subscriptionPollInterval",
            "subscriptionNewVideos",
        ]
    }

    private static let maxLogEntries = 250
    private static let diskSpaceSafetyMarginBytes: Int64 = 64 * 1_048_576

    // MARK: - Probe

    @Published var inputURL: String = "" {
        didSet {
            guard inputURL != oldValue, !isPlaylistInputURL else { return }
            if playlistConfig != PlaylistConfig() { playlistConfig = PlaylistConfig() }
        }
    }

    @Published var probeState: ProbeState = .idle
    @Published var playlistConfig = PlaylistConfig() {
        didSet {
            guard playlistConfig.mode != oldValue.mode else { return }
            var updated = playlistConfig
            if updated.mode != .wholePlaylistBestVideo {
                updated.videoQualityStrategy = .bestCompatibility
            }
            if updated.mode != .wholePlaylistBestAudio {
                updated.audioQualityStrategy = .moreCompatible
            }
            if updated.mode == .onlyFirstItem {
                updated.subtitleMode = .none
                updated.subtitleLanguage = ""
                updated.segmentMode = .fullItem
                updated.segmentRange = ""
                updated.formatMode = .unifiedStrategy
                updated.perItemFormatMap = ""
            }
            if updated != playlistConfig { playlistConfig = updated }
        }
    }

    // MARK: - Format selection

    @Published var selectedVideoFormat: VideoFormat?
    @Published var selectedAudioFormat: AudioFormat?
    @Published var selectedSubtitle: SubtitleTrack?
    @Published var audioTranscodeFormat: AudioTranscodeFormat = .original
    @Published var cookiesFilePath: String = ""
    @Published var extraYtDlpArguments: String = "" {
        didSet { cachedParsedExtraOptions = Result { try parseExtraOptions(extraYtDlpArguments) } }
    }

    private(set) var cachedParsedExtraOptions: Result<[ParsedExtraOption], Error> = .success([])
    @Published var downloaderPreference: DownloaderPreference = .native {
        didSet { defaults.set(downloaderPreference.rawValue, forKey: StorageKey.downloaderPreference) }
    }

    @Published private(set) var aria2cAvailable: Bool = false

    // MARK: - Queue

    @Published var appMode: AppMode = .single
    @Published var queueInputURLs: String = ""
    @Published var queueQualityStrategy: QueueQualityStrategy = .bestQuality
    @Published var queueError: String?
    /// Tracks the count for queue validation errors so they can be
    /// re-localized when the user switches language (even after the
    /// input field is cleared on partial submit).
    private var queueUnsupportedCount = 0
    @Published var subscriptionInputURL: String = ""
    let downloadQueue = DownloadQueue()
    let historyStore: DownloadHistoryStore

    // MARK: - Subscriptions

    let subscriptionStore: ChannelSubscriptionStore
    private(set) lazy var pollingManager = SubscriptionPollingManager(
        store: subscriptionStore,
        defaults: defaults,
        onBilibiliLog: makeServiceLogger(scope: .feed)
    )

    // MARK: - Update

    @Published var updateState: UpdateState = .idle
    @Published var currentYtDlpVersion: String?
    @Published var updateChannel: UpdateChannel = .stable {
        didSet { defaults.set(updateChannel.rawValue, forKey: StorageKey.updateChannel) }
    }

    @Published var autoCheckForUpdates: Bool = true {
        didSet { defaults.set(autoCheckForUpdates, forKey: StorageKey.autoCheckForUpdates) }
    }

    @Published var autoCheckForAppUpdates: Bool = true {
        didSet { defaults.set(autoCheckForAppUpdates, forKey: StorageKey.autoCheckForAppUpdates) }
    }

    @Published var language: AppLanguage = .english {
        didSet {
            defaults.set(language.rawValue, forKey: StorageKey.appLanguage)
            // Sync with system AppleLanguages so AppKit frameworks (e.g. Sparkle)
            // pick the same language as the in-app setting.
            defaults.set([language.rawValue], forKey: "AppleLanguages")
            refreshValidationErrors()
        }
    }

    @Published var appearance: AppAppearance = .system {
        didSet {
            defaults.set(appearance.rawValue, forKey: StorageKey.appAppearance)
            applyAppearance()
        }
    }

    @Published var showTechnicalDetails: Bool = false {
        didSet { defaults.set(showTechnicalDetails, forKey: StorageKey.showTechnicalDetails) }
    }

    @Published var showAllFormats: Bool = false {
        didSet { defaults.set(showAllFormats, forKey: StorageKey.showAllFormats) }
    }

    var ytDlpSource: String {
        FileManager.default.fileExists(atPath: BundledToolLocator.userLocalURL(for: .ytDlp).path)
            ? "user-installed" : "bundled"
    }

    // MARK: - Output directory

    @Published var selectedOutputDirectory: URL? {
        didSet {
            if let path = selectedOutputDirectory?.path(percentEncoded: false) {
                defaults.set(path, forKey: StorageKey.selectedOutputDirectoryPath)
            } else {
                defaults.removeObject(forKey: StorageKey.selectedOutputDirectoryPath)
            }
        }
    }

    // MARK: - Download

    @Published var downloadState: DownloadState = .idle
    @Published private(set) var logs: [AppLogEntry] = []
    @Published private(set) var ffmpegWarningMessage: String?
    @Published private(set) var localDataStatusMessage: String?

    // MARK: - Private

    private let probeService = YtDlpProbeService()
    private var downloadRunner = ProcessRunner()
    private let defaults: UserDefaults
    private var probeTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var latestRelease: YtDlpReleaseInfo?
    private var probeAttemptID: Int = 0
    private var downloadAttemptID: Int = 0
    private let userLocalBinariesDirectory: URL

    init(
        defaults: UserDefaults = .standard,
        historyStore: DownloadHistoryStore? = nil,
        subscriptionStore: ChannelSubscriptionStore? = nil,
        userLocalBinariesDirectory: URL = BundledToolLocator.userLocalBinariesDirectory
    ) {
        self.defaults = defaults
        self.historyStore = historyStore ?? DownloadHistoryStore()
        self.subscriptionStore = subscriptionStore ?? ChannelSubscriptionStore()
        self.userLocalBinariesDirectory = userLocalBinariesDirectory

        if let path = defaults.string(forKey: StorageKey.selectedOutputDirectoryPath),
           !path.isEmpty,
           Self.isUsableDirectory(URL(fileURLWithPath: path))
        {
            selectedOutputDirectory = URL(fileURLWithPath: path)
        } else {
            selectedOutputDirectory = nil
            defaults.removeObject(forKey: StorageKey.selectedOutputDirectoryPath)
        }

        if let raw = defaults.string(forKey: StorageKey.downloaderPreference),
           let pref = DownloaderPreference(rawValue: raw)
        {
            downloaderPreference = pref
        }
        aria2cAvailable = Aria2cLocator().findAria2c() != nil

        if let raw = defaults.string(forKey: StorageKey.updateChannel),
           let channel = UpdateChannel(rawValue: raw)
        {
            updateChannel = channel
        }
        if defaults.object(forKey: StorageKey.autoCheckForUpdates) != nil {
            autoCheckForUpdates = defaults.bool(forKey: StorageKey.autoCheckForUpdates)
        }
        if defaults.object(forKey: StorageKey.autoCheckForAppUpdates) != nil {
            autoCheckForAppUpdates = defaults.bool(forKey: StorageKey.autoCheckForAppUpdates)
        }
        if let raw = defaults.string(forKey: StorageKey.appLanguage),
           let lang = AppLanguage(rawValue: raw)
        {
            language = lang
        }
        // Ensure AppleLanguages is in sync on every launch.
        defaults.set([language.rawValue], forKey: "AppleLanguages")
        if let raw = defaults.string(forKey: StorageKey.appAppearance),
           let saved = AppAppearance(rawValue: raw)
        {
            appearance = saved
        }
        if defaults.object(forKey: StorageKey.showTechnicalDetails) != nil {
            showTechnicalDetails = defaults.bool(forKey: StorageKey.showTechnicalDetails)
        }
        if defaults.object(forKey: StorageKey.showAllFormats) != nil {
            showAllFormats = defaults.bool(forKey: StorageKey.showAllFormats)
        }
        applyAppearance()

        refreshFFmpegWarning()

        Task { @MainActor [weak self] in
            await self?.performStartupUpdateTasks()
        }
    }

    // MARK: - Probe

    func probe() {
        guard !isWholePlaylistDownload else { return }
        let url = trimmedInputURL
        guard !url.isEmpty else { return }

        guard isSupportedVideoHost(url) else {
            probeState = .failure(unsupportedURLError())
            appendLog(scope: .probe, level: .error, message: "URL is not from a supported video platform: \(url)")
            return
        }

        probeTask?.cancel()
        let attemptID = beginProbeAttempt()
        appendLog(scope: .probe, level: .info, message: "Starting probe for \(url)")
        probeState = .loading
        selectedVideoFormat = nil
        selectedAudioFormat = nil
        selectedSubtitle = nil
        downloadState = .idle

        probeTask = Task {
            let normalizedCookiesFilePath: String?
            let parsedOptions: [ParsedExtraOption]
            do {
                normalizedCookiesFilePath = try normalizedCookiesFilePathOrThrow()
                parsedOptions = try parsedExtraOptionsOrThrow()
            } catch let error as AppError {
                await MainActor.run {
                    guard isCurrentProbeAttempt(attemptID) else { return }
                    probeTask = nil
                    probeState = .failure(error)
                    appendLog(scope: .probe, level: .error, message: joinedErrorMessage(error))
                }
                return
            } catch {
                await MainActor.run {
                    guard isCurrentProbeAttempt(attemptID) else { return }
                    probeTask = nil
                    probeState = .failure(AppError(
                        message: "Probe failed.",
                        recoverySuggestion: error.localizedDescription
                    ))
                    appendLog(scope: .probe, level: .error, message: "Probe failed. \(error.localizedDescription)")
                }
                return
            }

            do {
                let info = try await probeService.probe(
                    url: url,
                    cookiesFilePath: normalizedCookiesFilePath,
                    extraOptions: parsedOptions,
                    onLog: makeServiceLogger(scope: .probe)
                )
                await MainActor.run {
                    guard isCurrentProbeAttempt(attemptID) else { return }
                    probeTask = nil
                    probeState = .success(info)
                    autoSelectFormats(from: info)
                    appendLog(
                        scope: .probe,
                        level: .success,
                        message: "Ready: \(info.title) (\(info.videoFormats.count) video / \(info.audioFormats.count) audio)"
                    )
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard isCurrentProbeAttempt(attemptID) else { return }
                    probeTask = nil
                }
            } catch let error as AppError {
                await MainActor.run {
                    guard isCurrentProbeAttempt(attemptID) else { return }
                    probeTask = nil
                    let mappedError = mapYtDlpError(error, url: url, cookiesFilePath: normalizedCookiesFilePath)
                    probeState = .failure(mappedError)
                    appendLog(scope: .probe, level: .error, message: joinedErrorMessage(mappedError))
                }
            } catch {
                await MainActor.run {
                    guard isCurrentProbeAttempt(attemptID) else { return }
                    probeTask = nil
                    let mappedError = mapYtDlpError(AppError(
                        message: "Probe failed.",
                        recoverySuggestion: error.localizedDescription
                    ), url: url, cookiesFilePath: normalizedCookiesFilePath)
                    probeState = .failure(mappedError)
                    appendLog(scope: .probe, level: .error, message: joinedErrorMessage(mappedError))
                }
            }
        }
    }

    // MARK: - Download

    var canDownload: Bool {
        guard validatedSelectedOutputDirectory != nil, !isDownloading else { return false }
        if isWholePlaylistDownload {
            return !trimmedInputURL.isEmpty
        }
        guard case .success = probeState else { return false }
        if hasNoSelectableFormatsAfterProbe {
            return true
        }
        guard selectedVideoFormat != nil || selectedAudioFormat != nil else { return false }
        return true
    }

    var isDownloading: Bool {
        if case .downloading = downloadState { return true }
        if case .preparing = downloadState { return true }
        return false
    }

    var trimmedInputURL: String {
        inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isPlaylistInputURL: Bool {
        Self.isPlaylistURL(inputURL)
    }

    var hasNoSelectableFormatsAfterProbe: Bool {
        guard !isWholePlaylistDownload, case let .success(info) = probeState else { return false }
        return info.videoFormats.isEmpty && info.audioFormats.isEmpty
    }

    var isWholePlaylistDownload: Bool {
        isPlaylistInputURL && playlistConfig.mode.downloadsWholePlaylist
    }

    var showsPlaylistVideoQualityStrategy: Bool {
        isPlaylistInputURL && playlistConfig.mode == .wholePlaylistBestVideo
    }

    var showsPlaylistAudioQualityStrategy: Bool {
        isPlaylistInputURL && playlistConfig.mode == .wholePlaylistBestAudio
    }

    func download() {
        let url = trimmedInputURL
        guard !url.isEmpty else { return }
        guard let outputDir = validatedSelectedOutputDirectory else {
            let error = AppError(
                message: "Selected output folder is unavailable.",
                recoverySuggestion: "Choose another output folder, then try again."
            )
            downloadState = .failed(error)
            appendLog(scope: .download, level: .error, message: joinedErrorMessage(error))
            return
        }

        let info: MediaInfo?
        if isWholePlaylistDownload {
            info = nil
        } else {
            guard case let .success(probedInfo) = probeState else { return }
            info = probedInfo
        }

        if let diskSpaceError = preflightDiskSpaceError(outputDirectory: outputDir) {
            downloadState = .failed(diskSpaceError)
            appendLog(scope: .download, level: .error, message: joinedErrorMessage(diskSpaceError))
            return
        }

        downloadTask?.cancel()
        let previousRunner = downloadRunner
        Task { try? await previousRunner.cancel() }
        downloadRunner = ProcessRunner()
        let attemptID = beginDownloadAttempt()
        downloadState = .idle

        let videoId = isWholePlaylistDownload ? nil : selectedVideoFormat?.id
        let audioId = isWholePlaylistDownload ? nil : selectedAudioFormat?.id
        let subtitleTrack: SubtitleTrack?
        let cookiesPath: String
        let parsedOptions: [ParsedExtraOption]
        let managedArgs: [String]
        do {
            subtitleTrack = try isWholePlaylistDownload
                ? wholePlaylistSubtitleTrackOrThrow()
                : selectedSubtitle
            cookiesPath = try normalizedCookiesFilePathOrThrow() ?? ""
            parsedOptions = try parsedExtraOptionsOrThrow()
            managedArgs = try isWholePlaylistDownload ? wholePlaylistArgumentsOrThrow() : []
        } catch let error as AppError {
            downloadState = .failed(error)
            appendLog(scope: .download, level: .error, message: joinedErrorMessage(error))
            return
        } catch {
            let mapped = AppError(message: "Invalid yt-dlp arguments.", recoverySuggestion: error.localizedDescription)
            downloadState = .failed(mapped)
            appendLog(scope: .download, level: .error, message: joinedErrorMessage(mapped))
            return
        }
        let capturedTitle = info?.title
        // nil for whole-playlist downloads by design (estimatedDownloadSizeBytes returns nil when isWholePlaylistDownload).
        let capturedEstimatedBytes = estimatedDownloadSizeBytes(
            video: selectedVideoFormat,
            audio: selectedAudioFormat
        )
        let effectiveTranscode = effectiveAudioTranscodeFormat(
            videoId: videoId,
            playlistMode: playlistConfig.mode,
            selectedFormat: audioTranscodeFormat
        )
        let resolvedAria2cPath: String? = if downloaderPreference == .aria2c {
            Aria2cLocator().findAria2c()?.path
        } else {
            nil
        }
        if downloaderPreference == .aria2c {
            aria2cAvailable = resolvedAria2cPath != nil
        }
        if downloaderPreference == .aria2c, resolvedAria2cPath == nil {
            appendLog(scope: .download, level: .warning, message: "aria2c not found in supported locations; falling back to built-in downloader")
        }

        let preview = buildCommandPreview(
            title: info?.title,
            videoId: videoId,
            audioId: audioId,
            subtitleTrack: subtitleTrack,
            audioTranscodeFormat: effectiveTranscode,
            cookiesFilePath: cookiesPath.isEmpty ? nil : cookiesPath,
            extraOptions: parsedOptions,
            managedArguments: managedArgs,
            playlistMode: playlistConfig.mode,
            playlistVideoQualityStrategy: playlistConfig.videoQualityStrategy,
            playlistAudioQualityStrategy: playlistConfig.audioQualityStrategy,
            outputDir: outputDir
        )
        appendLog(
            scope: .download,
            level: .info,
            message: isWholePlaylistDownload
                ? "Preparing whole-playlist download"
                : "Preparing download for \(info?.title ?? "item")"
        )
        if hasNoSelectableFormatsAfterProbe {
            appendLog(scope: .download, level: .info, message: "No selectable formats detected; fallback to best.")
        }
        appendLog(scope: .download, level: .info, message: preview)
        downloadState = .preparing(commandPreview: preview)

        let service = YtDlpDownloadService(runner: downloadRunner)

        downloadTask = Task {
            do {
                if isWholePlaylistDownload, playlistConfig.formatMode == .perItemMapping {
                    let perItemSelections = try parsePerItemFormatSelectionsOrThrow()
                    for item in perItemSelections {
                        guard isCurrentDownloadAttempt(attemptID) else { return }
                        appendLog(scope: .download, level: .info, message: "Downloading playlist item \(item.index) with format \(item.formatSelector)")
                        let itemManagedArgs = managedArgs + ["--playlist-items", "\(item.index)"]
                        let perItemTranscode = effectivePerItemAudioTranscodeFormat(
                            formatSelector: item.formatSelector,
                            selectedFormat: effectiveTranscode
                        )
                        for try await event in service.download(
                            url: url,
                            videoFormatId: nil,
                            audioFormatId: nil,
                            formatSelectorOverride: item.formatSelector,
                            includeNoPlaylistOverride: false,
                            audioTranscodeFormat: perItemTranscode,
                            cookiesFilePath: cookiesPath.isEmpty ? nil : cookiesPath,
                            extraOptions: parsedOptions,
                            managedArguments: itemManagedArgs,
                            selectedProtocols: [],
                            subtitleTrack: subtitleTrack,
                            outputDirectory: outputDir,
                            playlistMode: .onlyFirstItem,
                            playlistVideoQualityStrategy: playlistConfig.videoQualityStrategy,
                            playlistAudioQualityStrategy: playlistConfig.audioQualityStrategy,
                            aria2cPath: resolvedAria2cPath,
                            onLog: makeServiceLogger(scope: .download)
                        ) {
                            switch event {
                            case let .progress(progress):
                                await MainActor.run {
                                    guard isCurrentDownloadAttempt(attemptID) else { return }
                                    downloadState = .downloading(progress)
                                }
                            case .completed:
                                break
                            }
                        }
                    }
                    await MainActor.run {
                        guard isCurrentDownloadAttempt(attemptID) else { return }
                        downloadTask = nil
                        downloadState = .succeeded(outputURL: outputDir)
                        appendLog(scope: .download, level: .success, message: "Completed playlist per-item downloads")
                        self.recordDownloadResult(
                            url: url, title: capturedTitle,
                            outputURL: outputDir, succeeded: true,
                            estimatedSizeBytes: capturedEstimatedBytes
                        )
                    }
                } else {
                    var protocols: [String?] = []
                    if !isWholePlaylistDownload {
                        if let vf = selectedVideoFormat { protocols.append(vf.transportProtocol) }
                        if let af = selectedAudioFormat { protocols.append(af.transportProtocol) }
                    }
                    for try await event in service.download(
                        url: url,
                        videoFormatId: videoId,
                        audioFormatId: audioId,
                        audioTranscodeFormat: effectiveTranscode,
                        cookiesFilePath: cookiesPath.isEmpty ? nil : cookiesPath,
                        extraOptions: parsedOptions,
                        managedArguments: managedArgs,
                        selectedProtocols: protocols,
                        subtitleTrack: subtitleTrack,
                        outputDirectory: outputDir,
                        playlistMode: playlistConfig.mode,
                        playlistVideoQualityStrategy: playlistConfig.videoQualityStrategy,
                        playlistAudioQualityStrategy: playlistConfig.audioQualityStrategy,
                        aria2cPath: resolvedAria2cPath,
                        onLog: makeServiceLogger(scope: .download)
                    ) {
                        switch event {
                        case let .progress(progress):
                            await MainActor.run {
                                guard isCurrentDownloadAttempt(attemptID) else { return }
                                downloadState = .downloading(progress)
                            }
                        case let .completed(result):
                            await MainActor.run {
                                guard isCurrentDownloadAttempt(attemptID) else { return }
                                downloadTask = nil
                                downloadState = .succeeded(outputURL: result.outputURL)
                                appendLog(
                                    scope: .download,
                                    level: .success,
                                    message: "Completed: \(result.outputURL.path(percentEncoded: false))"
                                )
                                self.recordDownloadResult(
                                    url: url, title: capturedTitle,
                                    outputURL: result.outputURL, succeeded: true,
                                    estimatedSizeBytes: capturedEstimatedBytes
                                )
                            }
                        }
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard isCurrentDownloadAttempt(attemptID) else { return }
                    downloadTask = nil
                    downloadState = .cancelled
                    appendLog(scope: .download, level: .warning, message: "Download task was cancelled")
                }
            } catch let error as AppError {
                await MainActor.run {
                    guard isCurrentDownloadAttempt(attemptID) else { return }
                    downloadTask = nil
                    let mappedError = mapYtDlpError(error, url: url, cookiesFilePath: cookiesPath.isEmpty ? nil : cookiesPath)
                    downloadState = .failed(mappedError)
                    appendLog(scope: .download, level: .error, message: joinedErrorMessage(mappedError))
                    self.recordDownloadResult(
                        url: url, title: capturedTitle,
                        outputURL: nil, succeeded: false,
                        estimatedSizeBytes: capturedEstimatedBytes,
                        sendNotification: false
                    )
                }
            } catch {
                await MainActor.run {
                    guard isCurrentDownloadAttempt(attemptID) else { return }
                    downloadTask = nil
                    let mappedError = mapYtDlpError(AppError(
                        message: "Download failed.",
                        recoverySuggestion: error.localizedDescription
                    ), url: url, cookiesFilePath: cookiesPath.isEmpty ? nil : cookiesPath)
                    downloadState = .failed(mappedError)
                    appendLog(scope: .download, level: .error, message: joinedErrorMessage(mappedError))
                    self.recordDownloadResult(
                        url: url, title: capturedTitle,
                        outputURL: nil, succeeded: false,
                        estimatedSizeBytes: capturedEstimatedBytes,
                        sendNotification: false
                    )
                }
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        invalidateDownloadAttempt()
        downloadTask = nil
        Task { try? await downloadRunner.cancel() }
        downloadState = .cancelled
        appendLog(scope: .download, level: .warning, message: "Cancel requested")
    }

    func resetDownload() {
        inputURL = ""
        probeState = .idle
        selectedVideoFormat = nil
        selectedAudioFormat = nil
        selectedSubtitle = nil
        downloadState = .idle
    }

    func retryDownload() {
        downloadTask?.cancel()
        invalidateDownloadAttempt()
        downloadTask = nil
        // download() creates its own fresh ProcessRunner, so just cancel
        // the current one — no need to allocate an intermediate runner.
        let previousRunner = downloadRunner
        Task { try? await previousRunner.cancel() }
        downloadState = .idle
        download()
    }

    // MARK: - Queue

    func addToQueue() {
        queueError = nil
        queueUnsupportedCount = 0

        guard let outputDir = validatedSelectedOutputDirectory else {
            queueError = Loc.queueNeedFolder(language)
            appendLog(scope: .download, level: .error, message: "Select an output folder before adding to queue.")
            return
        }

        let allURLs = parseLines(queueInputURLs)

        guard !allURLs.isEmpty else { return }

        let supported = allURLs.filter { isSupportedVideoHost($0) }
        let unsupportedCount = allURLs.count - supported.count

        guard !supported.isEmpty else {
            queueUnsupportedCount = unsupportedCount
            queueError = Loc.queueUnsupportedURLs(unsupportedCount, language)
            appendLog(scope: .download, level: .warning, message: "\(unsupportedCount) URL(s) skipped: not from a supported video platform")
            return
        }

        let normalizedCookies: String?
        let parsedExtra: [ParsedExtraOption]
        do {
            normalizedCookies = try normalizedCookiesFilePathOrThrow()
            parsedExtra = try parsedExtraOptionsOrThrow()
        } catch let error as AppError {
            queueError = joinedErrorMessage(error)
            appendLog(scope: .download, level: .error, message: joinedErrorMessage(error))
            return
        } catch {
            queueError = error.localizedDescription
            appendLog(scope: .download, level: .error, message: "Invalid arguments: \(error.localizedDescription)")
            return
        }

        let config = QueueItemConfig(
            outputDirectory: outputDir,
            cookiesFilePath: normalizedCookies,
            extraOptions: parsedExtra,
            audioTranscodeFormat: audioTranscodeFormat,
            downloaderPreference: downloaderPreference,
            aria2cPath: resolvedAria2cPathForQueue(),
            qualityStrategy: queueQualityStrategy
        )

        downloadQueue.addURLs(supported, config: config)
        queueInputURLs = ""
        if unsupportedCount > 0 {
            queueUnsupportedCount = unsupportedCount
            queueError = Loc.queueUnsupportedURLs(unsupportedCount, language)
            appendLog(scope: .download, level: .warning, message: "\(unsupportedCount) URL(s) skipped: not from a supported video platform")
        } else {
            queueError = nil
        }
        appendLog(scope: .download, level: .info, message: "Added \(supported.count) URL(s) to queue")
    }

    /// Directly add a single URL to the download queue (used by Subs "add" button).
    /// Returns true on success.
    @discardableResult
    func addSingleURLToQueue(_ url: String) -> Bool {
        guard isSupportedVideoHost(url) else {
            queueUnsupportedCount = 1
            queueError = Loc.queueUnsupportedURLs(1, language)
            appendLog(scope: .download, level: .warning, message: "URL skipped: \(url) is not from a supported video platform")
            return false
        }

        guard let outputDir = validatedSelectedOutputDirectory else {
            queueError = Loc.queueNeedFolder(language)
            return false
        }

        let normalizedCookies: String?
        let parsedExtra: [ParsedExtraOption]
        do {
            normalizedCookies = try normalizedCookiesFilePathOrThrow()
            parsedExtra = try parsedExtraOptionsOrThrow()
        } catch let error as AppError {
            queueError = joinedErrorMessage(error)
            appendLog(scope: .download, level: .error, message: joinedErrorMessage(error))
            return false
        } catch {
            queueError = error.localizedDescription
            appendLog(scope: .download, level: .error, message: "Invalid arguments: \(error.localizedDescription)")
            return false
        }

        let config = QueueItemConfig(
            outputDirectory: outputDir,
            cookiesFilePath: normalizedCookies,
            extraOptions: parsedExtra,
            audioTranscodeFormat: audioTranscodeFormat,
            downloaderPreference: downloaderPreference,
            aria2cPath: resolvedAria2cPathForQueue(),
            qualityStrategy: queueQualityStrategy
        )

        downloadQueue.addURLs([url], config: config)
        queueUnsupportedCount = 0
        queueError = nil
        appendLog(scope: .download, level: .info, message: "Added \(url) to queue from subscriptions")
        return true
    }

    private func resolvedAria2cPathForQueue() -> String? {
        guard downloaderPreference == .aria2c else { return nil }
        let path = Aria2cLocator().findAria2c()?.path
        aria2cAvailable = path != nil
        if path == nil {
            appendLog(scope: .download, level: .warning, message: "aria2c not found in supported locations; falling back to built-in downloader")
        }
        return path
    }

    @discardableResult
    func importURLs(from newText: String) -> URLImportResult {
        let existingLines = Set(parseLines(queueInputURLs))
        let allLines = parseLines(newText)

        let incoming = allLines.filter { line in
            let lower = line.lowercased()
            return lower.hasPrefix("http://") || lower.hasPrefix("https://")
        }
        let filteredCount = allLines.count - incoming.count

        let supported = incoming.filter { isSupportedVideoHost($0) }
        let unsupportedCount = incoming.count - supported.count

        var seen = existingLines
        var unique: [String] = []
        for url in supported {
            if seen.insert(url).inserted {
                unique.append(url)
            }
        }

        if !unique.isEmpty {
            let base = queueInputURLs.trimmingCharacters(in: .whitespacesAndNewlines)
            let separator = base.isEmpty ? "" : "\n"
            queueInputURLs = base + separator + unique.joined(separator: "\n")
        }

        return URLImportResult(
            importedCount: unique.count,
            skippedCount: supported.count - unique.count,
            filteredCount: filteredCount,
            unsupportedCount: unsupportedCount
        )
    }

    func importURLsFromFile(at url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            appendLog(scope: .download, level: .error, message: "Could not read file: \(url.lastPathComponent)")
            return
        }
        let result = importURLs(from: content)
        let level: AppLogLevel = result.importedCount == 0 ? .warning : .info
        appendLog(scope: .download, level: level, message: importLogMessage("file", result))
    }

    func importURLsFromClipboard(content: String?) {
        guard let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendLog(scope: .download, level: .warning, message: "Clipboard is empty or contains no text")
            return
        }
        let result = importURLs(from: content)
        let level: AppLogLevel = result.importedCount == 0 ? .warning : .info
        appendLog(scope: .download, level: level, message: importLogMessage("clipboard", result))
    }

    // MARK: - Local data

    @discardableResult
    func backupLocalData(fileManager: FileManager = .default) throws -> URL {
        let backupRoot = try localDataBackupRoot(fileManager: fileManager)
        let backupURL = backupRoot.appendingPathComponent("backup-\(Self.backupTimestamp())", isDirectory: true)
        try fileManager.createDirectory(at: backupURL, withIntermediateDirectories: true)

        let defaultsData = try PropertyListSerialization.data(
            fromPropertyList: Self.localDefaultsPayload(from: defaults),
            format: .xml,
            options: 0
        )
        try defaultsData.write(to: backupURL.appendingPathComponent("defaults.plist"), options: .atomic)

        try copyIfPresent(historyStore.storageURL, to: backupURL.appendingPathComponent("download_history.json"), fileManager: fileManager)
        try copyIfPresent(subscriptionStore.storageURL, to: backupURL.appendingPathComponent("channel_subscriptions.json"), fileManager: fileManager)
        try copyIfPresent(userLocalBinariesDirectory, to: backupURL.appendingPathComponent("Binaries", isDirectory: true), fileManager: fileManager)

        let defaultsPlist = backupURL.appendingPathComponent("defaults.plist")
        guard fileManager.fileExists(atPath: defaultsPlist.path),
              (try? fileManager.attributesOfItem(atPath: defaultsPlist.path)[.size] as? UInt64) ?? 0 > 0
        else {
            throw AppError(
                message: "Backup validation failed.",
                recoverySuggestion: "defaults.plist was not created in the backup directory. Aborting to prevent data loss."
            )
        }

        localDataStatusMessage = "Local data backup created: \(backupURL.lastPathComponent)"
        return backupURL
    }

    @discardableResult
    func clearLocalData(fileManager: FileManager = .default) throws -> URL {
        guard !isDownloadOrQueueActive else {
            throw AppError(message: "Cannot clear local data while downloads are active.", recoverySuggestion: "Cancel or wait for active downloads, then try again.")
        }

        let backupURL = try backupLocalData(fileManager: fileManager)
        pollingManager.clearStoredData()
        try historyStore.clearStoredData(fileManager: fileManager)
        try subscriptionStore.clearStoredData(fileManager: fileManager)

        let userBinaries = userLocalBinariesDirectory
        if fileManager.fileExists(atPath: userBinaries.path) {
            try fileManager.removeItem(at: userBinaries)
        }

        selectedOutputDirectory = nil
        downloaderPreference = .native
        aria2cAvailable = Aria2cLocator().findAria2c() != nil
        updateChannel = .stable
        autoCheckForUpdates = true
        autoCheckForAppUpdates = true
        language = .english
        appearance = .system
        showTechnicalDetails = false
        showAllFormats = false
        for key in StorageKey.localDataKeys {
            defaults.removeObject(forKey: key)
        }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("subscriptionNewVideos.corruptBackup.") {
            defaults.removeObject(forKey: key)
        }

        localDataStatusMessage = "Local data cleared. Backup: \(backupURL.lastPathComponent)"
        appendLog(scope: .app, level: .success, message: localDataStatusMessage ?? "Local data cleared")
        return backupURL
    }

    func restoreLocalData(from backupURL: URL, fileManager: FileManager = .default) throws {
        guard !isDownloadOrQueueActive else {
            throw AppError(message: "Cannot restore local data while downloads are active.", recoverySuggestion: "Cancel or wait for active downloads, then try again.")
        }

        if let defaultsPayload = try Self.loadDefaultsPayload(from: backupURL.appendingPathComponent("defaults.plist")) {
            for key in StorageKey.localDataKeys {
                defaults.removeObject(forKey: key)
            }
            for (key, value) in defaultsPayload {
                defaults.set(value, forKey: key)
            }
        }

        try restoreIfPresent(backupURL.appendingPathComponent("download_history.json"), to: historyStore.storageURL, fileManager: fileManager)
        try restoreIfPresent(backupURL.appendingPathComponent("channel_subscriptions.json"), to: subscriptionStore.storageURL, fileManager: fileManager)
        try restoreIfPresent(backupURL.appendingPathComponent("Binaries", isDirectory: true), to: userLocalBinariesDirectory, fileManager: fileManager)

        historyStore.reload()
        subscriptionStore.reload()
        pollingManager.reloadStoredData()
        reloadPreferencesFromDefaults()
        localDataStatusMessage = "Local data restored from \(backupURL.lastPathComponent)"
        appendLog(scope: .app, level: .success, message: localDataStatusMessage ?? "Local data restored")
    }

    private func parseLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func importLogMessage(_ source: String, _ result: URLImportResult) -> String {
        var parts = ["Imported \(result.importedCount) URL(s) from \(source)"]
        if result.skippedCount > 0 { parts.append("skipped \(result.skippedCount) duplicate(s)") }
        if result.filteredCount > 0 { parts.append("filtered \(result.filteredCount) non-URL line(s)") }
        if result.unsupportedCount > 0 { parts.append("rejected \(result.unsupportedCount) unsupported URL(s)") }
        return parts.joined(separator: ", ")
    }

    func startQueue() {
        downloadQueue.startProcessing(
            locator: BundledToolLocator(),
            onLog: { [weak self] scope, level, message in
                self?.appendLog(scope: scope, level: level, message: message)
            },
            onItemCompleted: { [weak self] item in
                self?.recordDownloadResult(
                    url: item.url,
                    title: item.title,
                    outputURL: item.outputURL,
                    succeeded: item.status == .completed,
                    estimatedSizeBytes: nil,
                    sendNotification: false
                )
            }
        )
    }

    // MARK: - Update

    func checkForUpdate() {
        switch updateState {
        case .checking, .downloading, .verifying:
            return
        default:
            break
        }

        updateTask?.cancel()
        latestRelease = nil
        updateState = .checking
        appendLog(scope: .update, level: .info, message: "Checking for updates (\(updateChannel.label) channel)...")

        updateTask = Task {
            do {
                let service = YtDlpUpdateService()
                let release = try await service.fetchLatestRelease(channel: updateChannel)
                let current = currentYtDlpVersion ?? "unknown"

                latestRelease = release
                if current != "unknown", !Self.isVersionNewer(release.version, than: current) {
                    updateState = .upToDate(version: current)
                    appendLog(scope: .update, level: .success, message: "yt-dlp is up to date (\(current))")
                } else {
                    updateState = .available(current: current, latest: release.version)
                    appendLog(
                        scope: .update, level: .info,
                        message: "Update available: \(current) \u{2192} \(release.version)"
                    )
                }
            } catch is CancellationError {
                // ignored
            } catch {
                let mapped = (error as? AppError) ?? AppError(
                    message: "Update check failed.",
                    recoverySuggestion: error.localizedDescription
                )
                updateState = .failed(mapped)
                appendLog(scope: .update, level: .error, message: "Update check failed: \(error.localizedDescription)")
            }
        }
    }

    func installUpdate() {
        guard case .available = updateState, let release = latestRelease else { return }

        updateTask?.cancel()
        updateState = .downloading(progress: 0)
        appendLog(scope: .update, level: .info, message: "Downloading yt-dlp \(release.version)...")

        updateTask = Task {
            do {
                let service = YtDlpUpdateService()
                let newVersion = try await service.install(
                    from: release,
                    onProgress: { [weak self] progress in
                        Task { @MainActor in
                            self?.updateState = .downloading(progress: progress)
                        }
                    },
                    onVerifying: { [weak self] in
                        Task { @MainActor in
                            self?.updateState = .verifying
                            self?.appendLog(scope: .update, level: .info, message: "Verifying and installing...")
                        }
                    }
                )

                await refreshCurrentYtDlpVersion()
                updateState = .completed(newVersion: newVersion)
                appendLog(scope: .update, level: .success, message: "yt-dlp updated to \(newVersion)")
            } catch is CancellationError {
                updateState = .idle
            } catch {
                let mapped = (error as? AppError) ?? AppError(
                    message: "Update failed.",
                    recoverySuggestion: error.localizedDescription
                )
                updateState = .failed(mapped)
                appendLog(scope: .update, level: .error, message: "Update failed: \(error.localizedDescription)")
            }
        }
    }

    private func performStartupUpdateTasks() async {
        let service = YtDlpUpdateService()
        let isValid = await service.validateUserLocalBinary()
        if !isValid {
            try? FileManager.default.removeItem(at: BundledToolLocator.userLocalURL(for: .ytDlp))
            appendLog(
                scope: .update, level: .warning,
                message: "Removed invalid user-local yt-dlp, falling back to bundled"
            )
        }

        await refreshCurrentYtDlpVersion()

        if autoCheckForUpdates {
            checkForUpdate()
        }
    }

    private func refreshCurrentYtDlpVersion() async {
        let service = YtDlpUpdateService()
        currentYtDlpVersion = await service.currentVersion()
    }

    /// yt-dlp tags use YYYY.MM.DD (stable) or YYYY.MM.DD.XXXXXX (nightly);
    /// lexicographic comparison is correct for these fixed-width date-based formats.
    nonisolated static func isVersionNewer(_ latest: String, than current: String) -> Bool {
        latest > current
    }

    // MARK: - Auto-select

    private func autoSelectFormats(from info: MediaInfo) {
        let videos = filterVideoFormats(info.videoFormats, excludeHLS: true)
        let audios = filterAudioFormats(info.audioFormats, excludeHLS: true)

        let fallbackVideos = videos.isEmpty ? filterVideoFormats(info.videoFormats) : videos
        let fallbackAudios = audios.isEmpty ? filterAudioFormats(info.audioFormats) : audios

        selectedVideoFormat = fallbackVideos.first(where: { $0.resolution == "1080p" })
            ?? fallbackVideos.first
        selectedAudioFormat = fallbackAudios.first
    }

    // MARK: - Helpers

    var isDownloadOrQueueActive: Bool {
        if downloadQueue.isProcessing { return true }
        switch downloadState {
        case .preparing, .downloading:
            return true
        case .idle, .succeeded, .failed, .cancelled:
            return false
        }
    }

    private func localDataBackupRoot(fileManager: FileManager) throws -> URL {
        let base = historyStore.storageURL?.deletingLastPathComponent()
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YTTool", isDirectory: true)
        let backupRoot = base.appendingPathComponent("Backups", isDirectory: true)
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        return backupRoot
    }

    private func copyIfPresent(_ source: URL?, to destination: URL, fileManager: FileManager) throws {
        guard let source, fileManager.fileExists(atPath: source.path) else { return }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private func restoreIfPresent(_ source: URL, to destination: URL?, fileManager: FileManager) throws {
        guard let destination, fileManager.fileExists(atPath: source.path) else { return }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private static func localDefaultsPayload(from defaults: UserDefaults) -> [String: Any] {
        let snapshot = defaults.dictionaryRepresentation()
        var payload: [String: Any] = [:]
        for key in StorageKey.localDataKeys {
            if let value = snapshot[key] {
                payload[key] = value
            }
        }
        return payload
    }

    private static func loadDefaultsPayload(from url: URL) throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return plist as? [String: Any]
    }

    private static func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func reloadPreferencesFromDefaults() {
        if let path = defaults.string(forKey: StorageKey.selectedOutputDirectoryPath),
           !path.isEmpty,
           Self.isUsableDirectory(URL(fileURLWithPath: path))
        {
            selectedOutputDirectory = URL(fileURLWithPath: path)
        } else {
            selectedOutputDirectory = nil
        }

        downloaderPreference = defaults.string(forKey: StorageKey.downloaderPreference)
            .flatMap(DownloaderPreference.init(rawValue:)) ?? .native
        aria2cAvailable = Aria2cLocator().findAria2c() != nil
        updateChannel = defaults.string(forKey: StorageKey.updateChannel)
            .flatMap(UpdateChannel.init(rawValue:)) ?? .stable
        autoCheckForUpdates = defaults.object(forKey: StorageKey.autoCheckForUpdates) == nil
            ? true
            : defaults.bool(forKey: StorageKey.autoCheckForUpdates)
        autoCheckForAppUpdates = defaults.object(forKey: StorageKey.autoCheckForAppUpdates) == nil
            ? true
            : defaults.bool(forKey: StorageKey.autoCheckForAppUpdates)
        language = defaults.string(forKey: StorageKey.appLanguage)
            .flatMap(AppLanguage.init(rawValue:)) ?? .english
        appearance = defaults.string(forKey: StorageKey.appAppearance)
            .flatMap(AppAppearance.init(rawValue:)) ?? .system
        showTechnicalDetails = defaults.bool(forKey: StorageKey.showTechnicalDetails)
        showAllFormats = defaults.bool(forKey: StorageKey.showAllFormats)
        applyAppearance()
    }

    private func unsupportedURLError() -> AppError {
        AppError(kind: .unsupportedURL, message: Loc.queueUnsupportedURLs(1, language))
    }

    /// Re-localize stored validation errors when the user switches language.
    private func refreshValidationErrors() {
        // Probe validation error
        if case let .failure(error) = probeState,
           error.kind == .unsupportedURL
        {
            probeState = .failure(unsupportedURLError())
        }
        if case let .failure(error) = probeState,
           let localized = localizedCookiesError(kind: error.kind)
        {
            probeState = .failure(localized)
        }
        // Queue validation error (count persisted across input clears)
        if queueUnsupportedCount > 0, queueError != nil {
            queueError = Loc.queueUnsupportedURLs(queueUnsupportedCount, language)
        }
        // Cookie-related errors
        if case let .failed(error) = downloadState,
           let localized = localizedCookiesError(kind: error.kind)
        {
            downloadState = .failed(localized)
        }
    }

    func applyAppearance() {
        NSApp?.appearance = switch appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Call once from the main view's onAppear.
    /// Note: ad-hoc signed builds may not register with the notification center —
    /// use an Xcode dev build or Developer ID signing to test notifications.
    func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func appendLog(scope: AppLogScope, level: AppLogLevel, message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        logs.append(AppLogEntry(scope: scope, level: level, message: trimmed))
        if logs.count > Self.maxLogEntries {
            logs.removeFirst(logs.count - Self.maxLogEntries)
        }
    }

    func refreshFFmpegWarning(locator: BundledToolLocator = BundledToolLocator()) {
        let missing = locator.missingTools([.ffmpeg, .ffprobe])
        guard !missing.isEmpty else {
            ffmpegWarningMessage = nil
            return
        }
        ffmpegWarningMessage = ffmpegWarningMessage(for: missing)
    }

    @discardableResult
    func beginProbeAttempt() -> Int {
        probeAttemptID += 1
        return probeAttemptID
    }

    func isCurrentProbeAttempt(_ attemptID: Int) -> Bool {
        probeAttemptID == attemptID
    }

    @discardableResult
    func beginDownloadAttempt() -> Int {
        downloadAttemptID += 1
        return downloadAttemptID
    }

    @discardableResult
    func invalidateDownloadAttempt() -> Int {
        downloadAttemptID += 1
        return downloadAttemptID
    }

    func isCurrentDownloadAttempt(_ attemptID: Int) -> Bool {
        downloadAttemptID == attemptID
    }

    func estimatedDownloadSizeBytes(video: VideoFormat?, audio: AudioFormat?) -> Int64? {
        guard !isWholePlaylistDownload else { return nil }
        let sizes = [video?.fileSizeBytes, audio?.fileSizeBytes].compactMap { $0 }
        guard !sizes.isEmpty else { return nil }
        return sizes.reduce(0, +)
    }

    private func recordDownloadResult(
        url: String,
        title: String?,
        outputURL: URL?,
        succeeded: Bool,
        estimatedSizeBytes: Int64?,
        sendNotification: Bool = true
    ) {
        if sendNotification, succeeded, let outputURL {
            sendCompletionNotification(outputURL: outputURL)
        }
        historyStore.append(DownloadHistoryEntry(
            id: UUID(),
            url: url,
            title: title,
            outputPath: outputURL?.path(percentEncoded: false),
            dateCompleted: Date(),
            succeeded: succeeded,
            estimatedSizeBytes: estimatedSizeBytes
        ))
    }

    private func sendCompletionNotification(outputURL: URL?) {
        let content = UNMutableNotificationContent()
        content.title = Loc.notificationTitle(language)
        content.body = outputURL?.lastPathComponent ?? Loc.notificationBody(language)
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        appendLog(scope: .app, level: .info, message: "Posted completion notification")
    }

    private func makeServiceLogger(scope: AppLogScope) -> @Sendable (ServiceLogKind, String) -> Void {
        { [weak self] kind, message in
            Task { @MainActor in
                self?.appendLog(scope: scope, level: kind.appLogLevel, message: message)
            }
        }
    }

    private func joinedErrorMessage(_ error: AppError) -> String {
        if let suggestion = error.recoverySuggestion, !suggestion.isEmpty {
            return "\(error.message) \(suggestion)"
        }
        return error.message
    }

    private func preflightDiskSpaceError(outputDirectory: URL) -> AppError? {
        let estimatedBytes = estimatedDownloadSizeBytes(
            video: selectedVideoFormat,
            audio: selectedAudioFormat
        )
        guard let estimatedBytes,
              let availableBytes = availableDiskSpaceBytes(for: outputDirectory)
        else {
            return nil
        }

        if estimatedBytes + Self.diskSpaceSafetyMarginBytes <= availableBytes {
            return nil
        }

        return AppError(
            message: "Insufficient disk space.",
            recoverySuggestion: "Estimated download size is \(formatDiskBytes(estimatedBytes)), but only \(formatDiskBytes(availableBytes)) is available in the selected folder."
        )
    }

    private func availableDiskSpaceBytes(for directory: URL) -> Int64? {
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]
        guard let values = try? directory.resourceValues(forKeys: keys) else {
            return nil
        }

        if let important = values.volumeAvailableCapacityForImportantUsage {
            return important
        }
        if let legacy = values.volumeAvailableCapacity {
            return Int64(legacy)
        }
        return nil
    }

    private static let cookieExpiryPatterns = [
        "cookie", "sessdata", "expired", "login required",
        "cookies are not valid", "unable to log in", "precondition",
    ]

    private static let httpPreconditionStatusPatterns = [
        "http error 412", "http status 412", "status 412", "status code 412",
    ]

    func mapYtDlpError(_ error: AppError, url: String, cookiesFilePath: String?) -> AppError {
        let haystack = [error.message, error.recoverySuggestion]
            .compactMap { $0?.lowercased() }
            .joined(separator: "\n")

        if haystack.contains("no space left on device")
            || haystack.contains("enospc")
            || haystack.contains("disk full")
        {
            return AppError(
                message: "Insufficient disk space.",
                recoverySuggestion: "Free up disk space or choose another output folder, then try again."
            )
        }

        if isBilibiliURL(url),
           Self.cookieExpiryPatterns.contains(where: { haystack.contains($0) })
           || Self.httpPreconditionStatusPatterns.contains(where: { haystack.contains($0) })
        {
            let kind: AppError.Kind = Self.hasConfiguredCookies(cookiesFilePath) ? .cookieExpired : .needsCookies
            return localizedCookiesError(kind: kind) ?? error
        }

        return error
    }

    private func localizedCookiesError(kind: AppError.Kind) -> AppError? {
        switch kind {
        case .cookieExpired:
            AppError(
                kind: .cookieExpired,
                message: Loc.cookieExpiredMessage(language),
                recoverySuggestion: Loc.cookieExpiredSuggestion(language)
            )
        case .needsCookies:
            AppError(
                kind: .needsCookies,
                message: Loc.needsCookiesMessage(language),
                recoverySuggestion: Loc.needsCookiesSuggestion(language)
            )
        case .general, .unsupportedURL:
            nil
        }
    }

    private static func hasConfiguredCookies(_ cookiesFilePath: String?) -> Bool {
        cookiesFilePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func ffmpegWarningMessage(for missingTools: [BundledTool]) -> String {
        let detail = switch Set(missingTools) {
        case [.ffmpeg]:
            "ffmpeg is missing."
        case [.ffprobe]:
            "ffprobe is missing."
        default:
            "ffmpeg and ffprobe are missing."
        }

        return "\(detail)\nVideo and audio streams may fail to merge.\nReinstall development binaries or rebuild the app bundle."
    }

    private func buildCommandPreview(
        title: String?,
        videoId: String?,
        audioId: String?,
        subtitleTrack: SubtitleTrack?,
        audioTranscodeFormat: AudioTranscodeFormat?,
        cookiesFilePath: String?,
        extraOptions: [ParsedExtraOption],
        managedArguments: [String],
        playlistMode: PlaylistMode,
        playlistVideoQualityStrategy: PlaylistVideoQualityStrategy,
        playlistAudioQualityStrategy: PlaylistAudioQualityStrategy,
        outputDir: URL
    ) -> String {
        let format = buildFormatSelector(
            videoId: videoId,
            audioId: audioId,
            playlistMode: playlistMode,
            playlistVideoQualityStrategy: playlistVideoQualityStrategy,
            playlistAudioQualityStrategy: playlistAudioQualityStrategy
        )
        let playlistFlag = playlistMode.downloadsWholePlaylist ? "" : " --no-playlist"
        var subtitleFlags = ""
        if let subtitleTrack {
            let flag = subtitleTrack.isAuto ? "--write-auto-subs" : "--write-subs"
            subtitleFlags = " \(flag) --sub-langs \(subtitleTrack.lang)"
        }
        let cookiesFlags = (cookiesFilePath?.isEmpty == false) ? " --cookies \"<cookies-file>\"" : ""
        let transcodeFlags = audioTranscodeFormat?.ytDlpAudioFormat.map { " -x --audio-format \($0)" } ?? ""
        let rendered = renderExtraOptions(extraOptions, for: .download) + managedArguments
        let extraFlags = rendered.isEmpty ? "" : " " + rendered.joined(separator: " ")
        let target = title ?? "playlist items"
        return "yt-dlp -f \(format)\(playlistFlag)\(subtitleFlags)\(cookiesFlags)\(transcodeFlags)\(extraFlags) -o \"\(outputDir.lastPathComponent)/%(title)s [%(resolution)s].%(ext)s\" …  # \(target)"
    }

    private func formatDiskBytes(_ bytes: Int64) -> String {
        formatBytes(bytes)
    }

    private var validatedSelectedOutputDirectory: URL? {
        guard let url = selectedOutputDirectory, Self.isUsableDirectory(url) else {
            return nil
        }
        return url
    }

    private static func isPlaylistURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed) else {
            return trimmed.contains("list=")
        }

        if components.path == "/playlist" {
            return true
        }

        return components.queryItems?.contains {
            $0.name == "list" && !($0.value ?? "").isEmpty
        } == true
    }

    private static func isUsableDirectory(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func normalizedCookiesFilePathOrThrow() throws -> String? {
        let trimmed = cookiesFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = (trimmed as NSString).expandingTildeInPath
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: normalized, isDirectory: &isDirectory)
        guard exists, !isDirectory.boolValue else {
            throw AppError(
                message: "Cookies file path is invalid.",
                recoverySuggestion: "Use an existing cookies file path."
            )
        }
        guard FileManager.default.isReadableFile(atPath: normalized) else {
            throw AppError(
                message: "Cookies file is not readable.",
                recoverySuggestion: "Check file permissions, then try again."
            )
        }
        return normalized
    }

    private func parsedExtraOptionsOrThrow() throws -> [ParsedExtraOption] {
        try cachedParsedExtraOptions.get()
    }

    func wholePlaylistSubtitleTrackOrThrow() throws -> SubtitleTrack? {
        guard isWholePlaylistDownload else { return nil }
        guard playlistConfig.subtitleMode != .none else { return nil }

        let lang = playlistConfig.subtitleLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lang.isEmpty else {
            throw AppError(
                message: "Playlist subtitle language is required.",
                recoverySuggestion: "Enter a subtitle language code, for example en or zh-Hans."
            )
        }
        return SubtitleTrack(
            lang: lang,
            label: lang,
            isAuto: playlistConfig.subtitleMode == .auto
        )
    }

    func wholePlaylistArgumentsOrThrow() throws -> [String] {
        guard isWholePlaylistDownload else { return [] }
        guard playlistConfig.segmentMode == .fixedRange else { return [] }

        let raw = playlistConfig.segmentRange.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            throw AppError(
                message: "Playlist segment range is required.",
                recoverySuggestion: "Enter a range like 00:30-01:00."
            )
        }
        let normalized = raw.hasPrefix("*") ? raw : "*\(raw)"
        return ["--download-sections", normalized]
    }

    struct URLImportResult {
        let importedCount: Int
        let skippedCount: Int
        let filteredCount: Int
        let unsupportedCount: Int
    }

    struct PerItemFormatSelection {
        let index: Int
        let formatSelector: String
    }

    func parsePerItemFormatSelectionsOrThrow() throws -> [PerItemFormatSelection] {
        guard isWholePlaylistDownload, playlistConfig.formatMode == .perItemMapping else { return [] }

        let raw = playlistConfig.perItemFormatMap.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            throw AppError(
                message: "Per-item format mapping is required.",
                recoverySuggestion: "Use syntax like 1=137+140;2=136+140."
            )
        }

        let pairs = raw.split(separator: ";", omittingEmptySubsequences: true)
        var results: [PerItemFormatSelection] = []
        for pair in pairs {
            let token = pair.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }
            let parts = token.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                throw AppError(
                    message: "Invalid per-item mapping entry.",
                    recoverySuggestion: "Each entry must be itemIndex=formatSelector, for example 1=137+140."
                )
            }
            let indexRaw = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let formatRaw = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let index = Int(indexRaw), index > 0, !formatRaw.isEmpty else {
                throw AppError(
                    message: "Invalid per-item mapping entry.",
                    recoverySuggestion: "Item index must be a positive number and format selector cannot be empty."
                )
            }
            results.append(PerItemFormatSelection(index: index, formatSelector: formatRaw))
        }

        guard !results.isEmpty else {
            throw AppError(
                message: "Per-item format mapping is required.",
                recoverySuggestion: "Use syntax like 1=137+140;2=136+140."
            )
        }
        return results
    }

    private func effectiveAudioTranscodeFormat(
        videoId: String?,
        playlistMode: PlaylistMode,
        selectedFormat: AudioTranscodeFormat
    ) -> AudioTranscodeFormat? {
        guard selectedFormat != .original else { return nil }
        if playlistMode == .wholePlaylistBestAudio { return selectedFormat }
        if playlistMode == .onlyFirstItem, videoId == nil { return selectedFormat }
        return nil
    }

    func effectivePerItemAudioTranscodeFormat(
        formatSelector: String,
        selectedFormat: AudioTranscodeFormat?
    ) -> AudioTranscodeFormat? {
        guard let selectedFormat else { return nil }
        let normalized = formatSelector.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        if normalized.contains("+") { return nil }
        if normalized.contains("video") { return nil }
        return selectedFormat
    }
}
