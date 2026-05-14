import Foundation
import UserNotifications

enum AppMode: String, CaseIterable, Identifiable {
    case single
    case queue

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .single: "Single"
        case .queue: "Queue"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    private enum StorageKey {
        static let selectedOutputDirectoryPath = "selectedOutputDirectoryPath"
        static let downloaderPreference = "downloaderPreference"
        static let updateChannel = "updateChannel"
        static let autoCheckForUpdates = "autoCheckForUpdates"
    }

    private static let maxLogEntries = 250
    private static let diskSpaceSafetyMarginBytes: Int64 = 64 * 1_048_576

    // MARK: - Probe

    @Published var inputURL: String = "" {
        didSet {
            if !isPlaylistInputURL {
                playlistMode = .onlyFirstItem
                playlistVideoQualityStrategy = .bestCompatibility
                playlistAudioQualityStrategy = .moreCompatible
            }
        }
    }

    @Published var probeState: ProbeState = .idle
    @Published var playlistMode: PlaylistMode = .onlyFirstItem {
        didSet {
            if playlistMode != .wholePlaylistBestVideo {
                playlistVideoQualityStrategy = .bestCompatibility
            }
            if playlistMode != .wholePlaylistBestAudio {
                playlistAudioQualityStrategy = .moreCompatible
            }
            if playlistMode == .onlyFirstItem {
                playlistSubtitleMode = .none
                playlistSubtitleLanguage = ""
                playlistSegmentMode = .fullItem
                playlistSegmentRange = ""
                playlistFormatMode = .unifiedStrategy
                playlistPerItemFormatMap = ""
            }
        }
    }

    @Published var playlistVideoQualityStrategy: PlaylistVideoQualityStrategy = .bestCompatibility
    @Published var playlistAudioQualityStrategy: PlaylistAudioQualityStrategy = .moreCompatible
    @Published var playlistSubtitleMode: PlaylistSubtitleMode = .none
    @Published var playlistSubtitleLanguage: String = ""
    @Published var playlistSegmentMode: PlaylistSegmentMode = .fullItem
    @Published var playlistSegmentRange: String = ""
    @Published var playlistFormatMode: PlaylistFormatMode = .unifiedStrategy
    @Published var playlistPerItemFormatMap: String = ""

    // MARK: - Format selection

    @Published var selectedVideoFormat: VideoFormat?
    @Published var selectedAudioFormat: AudioFormat?
    @Published var selectedSubtitle: SubtitleTrack?
    @Published var audioTranscodeFormat: AudioTranscodeFormat = .original
    @Published var cookiesFilePath: String = ""
    @Published var extraYtDlpArguments: String = ""
    @Published var downloaderPreference: DownloaderPreference = .native {
        didSet { defaults.set(downloaderPreference.rawValue, forKey: StorageKey.downloaderPreference) }
    }

    @Published private(set) var aria2cAvailable: Bool = false

    // MARK: - Queue

    @Published var appMode: AppMode = .single
    @Published var queueInputURLs: String = ""
    let downloadQueue = DownloadQueue()
    let historyStore = DownloadHistoryStore()

    // MARK: - Update

    @Published var updateState: UpdateState = .idle
    @Published var currentYtDlpVersion: String?
    @Published var updateChannel: UpdateChannel = .stable {
        didSet { defaults.set(updateChannel.rawValue, forKey: StorageKey.updateChannel) }
    }

    @Published var autoCheckForUpdates: Bool = true {
        didSet { defaults.set(autoCheckForUpdates, forKey: StorageKey.autoCheckForUpdates) }
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

    // MARK: - Private

    private let probeService = YtDlpProbeService()
    private let downloadRunner = ProcessRunner()
    private let defaults: UserDefaults
    private var probeTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var latestRelease: YtDlpReleaseInfo?
    private var probeAttemptID: Int = 0
    private var downloadAttemptID: Int = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

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

        refreshFFmpegWarning()

        Task { @MainActor [weak self] in
            await self?.performStartupUpdateTasks()
        }
    }

    // MARK: - Probe

    func probe() {
        guard !isWholePlaylistDownload else { return }
        let url = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        probeTask?.cancel()
        let attemptID = beginProbeAttempt()
        appendLog(scope: .probe, level: .info, message: "Starting probe for \(url)")
        probeState = .loading
        selectedVideoFormat = nil
        selectedAudioFormat = nil
        selectedSubtitle = nil
        downloadState = .idle

        probeTask = Task {
            do {
                let normalizedCookiesFilePath = try normalizedCookiesFilePathOrThrow()
                let parsedExtraArguments = try parseExtraYtDlpArgumentsOrThrow()
                let info = try await probeService.probe(
                    url: url,
                    cookiesFilePath: normalizedCookiesFilePath,
                    extraArguments: parsedExtraArguments,
                    onLog: makeServiceLogger(scope: .probe)
                )
                await MainActor.run {
                    guard isCurrentProbeAttempt(attemptID) else { return }
                    probeTask = nil
                    probeState = .success(info)
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
                    probeState = .failure(error)
                    appendLog(scope: .probe, level: .error, message: joinedErrorMessage(error))
                }
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
            }
        }
    }

    // MARK: - Download

    var canDownload: Bool {
        guard validatedSelectedOutputDirectory != nil, !isDownloading else { return false }
        if isWholePlaylistDownload {
            return !inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    var isPlaylistInputURL: Bool {
        Self.isPlaylistURL(inputURL)
    }

    var hasNoSelectableFormatsAfterProbe: Bool {
        guard !isWholePlaylistDownload, case let .success(info) = probeState else { return false }
        return info.videoFormats.isEmpty && info.audioFormats.isEmpty
    }

    var isWholePlaylistDownload: Bool {
        isPlaylistInputURL && playlistMode.downloadsWholePlaylist
    }

    var showsPlaylistVideoQualityStrategy: Bool {
        isPlaylistInputURL && playlistMode == .wholePlaylistBestVideo
    }

    var showsPlaylistAudioQualityStrategy: Bool {
        isPlaylistInputURL && playlistMode == .wholePlaylistBestAudio
    }

    func download() {
        let url = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let attemptID = beginDownloadAttempt()
        downloadState = .idle

        let videoId = isWholePlaylistDownload ? nil : selectedVideoFormat?.id
        let audioId = isWholePlaylistDownload ? nil : selectedAudioFormat?.id
        let subtitleTrack: SubtitleTrack?
        let cookiesPath: String
        let passthroughArgs: [String]
        do {
            subtitleTrack = try isWholePlaylistDownload
                ? wholePlaylistSubtitleTrackOrThrow()
                : selectedSubtitle
            cookiesPath = try normalizedCookiesFilePathOrThrow() ?? ""
            passthroughArgs = try parseExtraYtDlpArgumentsOrThrow()
                + (isWholePlaylistDownload ? wholePlaylistArgumentsOrThrow() : [])
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
            playlistMode: playlistMode,
            selectedFormat: audioTranscodeFormat
        )
        let resolvedAria2cPath: String? = if downloaderPreference == .aria2c {
            Aria2cLocator().findAria2c()?.path
        } else {
            nil
        }
        if downloaderPreference == .aria2c, resolvedAria2cPath == nil {
            appendLog(scope: .download, level: .warning, message: "aria2c not found in PATH; falling back to built-in downloader")
        }

        let preview = buildCommandPreview(
            title: info?.title,
            videoId: videoId,
            audioId: audioId,
            subtitleTrack: subtitleTrack,
            audioTranscodeFormat: effectiveTranscode,
            cookiesFilePath: cookiesPath.isEmpty ? nil : cookiesPath,
            extraArguments: passthroughArgs,
            playlistMode: playlistMode,
            playlistVideoQualityStrategy: playlistVideoQualityStrategy,
            playlistAudioQualityStrategy: playlistAudioQualityStrategy,
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
                if isWholePlaylistDownload, playlistFormatMode == .perItemMapping {
                    let perItemSelections = try parsePerItemFormatSelectionsOrThrow()
                    for item in perItemSelections {
                        guard isCurrentDownloadAttempt(attemptID) else { return }
                        appendLog(scope: .download, level: .info, message: "Downloading playlist item \(item.index) with format \(item.formatSelector)")
                        let itemArgs = passthroughArgs + ["--playlist-items", "\(item.index)"]
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
                            extraArguments: itemArgs,
                            subtitleTrack: subtitleTrack,
                            outputDirectory: outputDir,
                            playlistMode: .onlyFirstItem,
                            playlistVideoQualityStrategy: playlistVideoQualityStrategy,
                            playlistAudioQualityStrategy: playlistAudioQualityStrategy,
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
                        self.sendCompletionNotification(outputURL: outputDir)
                        self.historyStore.append(DownloadHistoryEntry(
                            id: UUID(), url: url, title: capturedTitle,
                            outputPath: outputDir.path(percentEncoded: false),
                            dateCompleted: Date(), succeeded: true,
                            estimatedSizeBytes: capturedEstimatedBytes
                        ))
                    }
                } else {
                    for try await event in service.download(
                        url: url,
                        videoFormatId: videoId,
                        audioFormatId: audioId,
                        audioTranscodeFormat: effectiveTranscode,
                        cookiesFilePath: cookiesPath.isEmpty ? nil : cookiesPath,
                        extraArguments: passthroughArgs,
                        subtitleTrack: subtitleTrack,
                        outputDirectory: outputDir,
                        playlistMode: playlistMode,
                        playlistVideoQualityStrategy: playlistVideoQualityStrategy,
                        playlistAudioQualityStrategy: playlistAudioQualityStrategy,
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
                                self.sendCompletionNotification(outputURL: result.outputURL)
                                self.historyStore.append(DownloadHistoryEntry(
                                    id: UUID(), url: url, title: capturedTitle,
                                    outputPath: result.outputURL.path(percentEncoded: false),
                                    dateCompleted: Date(), succeeded: true,
                                    estimatedSizeBytes: capturedEstimatedBytes
                                ))
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
                    let mappedError = mapDownloadError(error)
                    downloadState = .failed(mappedError)
                    appendLog(scope: .download, level: .error, message: joinedErrorMessage(mappedError))
                    self.historyStore.append(DownloadHistoryEntry(
                        id: UUID(), url: url, title: capturedTitle,
                        outputPath: nil, dateCompleted: Date(), succeeded: false,
                        estimatedSizeBytes: capturedEstimatedBytes
                    ))
                }
            } catch {
                await MainActor.run {
                    guard isCurrentDownloadAttempt(attemptID) else { return }
                    downloadTask = nil
                    let mappedError = mapDownloadError(AppError(
                        message: "Download failed.",
                        recoverySuggestion: error.localizedDescription
                    ))
                    downloadState = .failed(mappedError)
                    appendLog(scope: .download, level: .error, message: joinedErrorMessage(mappedError))
                    self.historyStore.append(DownloadHistoryEntry(
                        id: UUID(), url: url, title: capturedTitle,
                        outputPath: nil, dateCompleted: Date(), succeeded: false,
                        estimatedSizeBytes: capturedEstimatedBytes
                    ))
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

    // MARK: - Queue

    func addToQueue() {
        guard let outputDir = validatedSelectedOutputDirectory else {
            appendLog(scope: .download, level: .error, message: "Select an output folder before adding to queue.")
            return
        }

        let urls = queueInputURLs
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !urls.isEmpty else { return }

        let normalizedCookies: String?
        let parsedExtra: [String]
        do {
            normalizedCookies = try normalizedCookiesFilePathOrThrow()
            parsedExtra = try parseShellLikeArguments(extraYtDlpArguments.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch let error as AppError {
            appendLog(scope: .download, level: .error, message: joinedErrorMessage(error))
            return
        } catch {
            appendLog(scope: .download, level: .error, message: "Invalid arguments: \(error.localizedDescription)")
            return
        }

        let config = QueueItemConfig(
            outputDirectory: outputDir,
            cookiesFilePath: normalizedCookies,
            extraArguments: parsedExtra,
            audioTranscodeFormat: audioTranscodeFormat,
            downloaderPreference: downloaderPreference
        )

        downloadQueue.addURLs(urls, config: config)
        queueInputURLs = ""
        appendLog(scope: .download, level: .info, message: "Added \(urls.count) URL(s) to queue")
    }

    @discardableResult
    func importURLs(from newText: String) -> URLImportResult {
        let existingLines = Set(
            queueInputURLs
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        let incoming = newText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = existingLines
        var unique: [String] = []
        for url in incoming {
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
            skippedCount: incoming.count - unique.count
        )
    }

    func importURLsFromFile(at url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            appendLog(scope: .download, level: .error, message: "Could not read file: \(url.lastPathComponent)")
            return
        }
        let result = importURLs(from: content)
        appendLog(
            scope: .download, level: .info,
            message: "Imported \(result.importedCount) URL(s) from file, skipped \(result.skippedCount) duplicate(s)"
        )
    }

    func importURLsFromClipboard(content: String?) {
        guard let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appendLog(scope: .download, level: .warning, message: "Clipboard is empty or contains no text")
            return
        }
        let result = importURLs(from: content)
        appendLog(
            scope: .download, level: .info,
            message: "Pasted \(result.importedCount) URL(s) from clipboard, skipped \(result.skippedCount) duplicate(s)"
        )
    }

    func startQueue() {
        downloadQueue.startProcessing(
            locator: BundledToolLocator(),
            onLog: { [weak self] scope, level, message in
                self?.appendLog(scope: scope, level: level, message: message)
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

    // MARK: - Helpers

    /// Call once from the main view's onAppear.
    /// Note: ad-hoc signed builds may not register with the notification center —
    /// use an Xcode dev build or Developer ID signing to test notifications.
    func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    print("[Notification] requestAuthorization error: \(error)")
                } else {
                    print("[Notification] authorization granted: \(granted)")
                }
            }
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

    private func sendCompletionNotification(outputURL: URL?) {
        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        content.body = outputURL?.lastPathComponent ?? "Your download has finished."
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
            let level: AppLogLevel = switch kind {
            case .command, .lifecycle, .stdout:
                .info
            case .stderr:
                .warning
            }
            Task { @MainActor in
                self?.appendLog(scope: scope, level: level, message: message)
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

    private func mapDownloadError(_ error: AppError) -> AppError {
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

        return error
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
        extraArguments: [String],
        playlistMode: PlaylistMode,
        playlistVideoQualityStrategy: PlaylistVideoQualityStrategy,
        playlistAudioQualityStrategy: PlaylistAudioQualityStrategy,
        outputDir: URL
    ) -> String {
        let format: String = switch playlistMode {
        case .onlyFirstItem:
            switch (videoId, audioId) {
            case let (v?, a?): "\(v)+\(a)"
            case let (v?, nil): v
            case let (nil, a?): a
            case (nil, nil): "best"
            }
        case .wholePlaylistBestVideo:
            switch playlistVideoQualityStrategy {
            case .bestCompatibility:
                "bestvideo+bestaudio/best"
            case .preferHigherQuality:
                "bv*+ba/b"
            }
        case .wholePlaylistBestAudio:
            switch playlistAudioQualityStrategy {
            case .moreCompatible:
                "ba/bestaudio/best"
            case .higherQuality:
                "bestaudio/best"
            }
        }
        let playlistFlag = playlistMode.downloadsWholePlaylist ? "" : " --no-playlist"
        var subtitleFlags = ""
        if let subtitleTrack {
            let flag = subtitleTrack.isAuto ? "--write-auto-subs" : "--write-subs"
            subtitleFlags = " \(flag) --sub-langs \(subtitleTrack.lang)"
        }
        let cookiesFlags = (cookiesFilePath?.isEmpty == false) ? " --cookies \"\(cookiesFilePath!)\"" : ""
        let transcodeFlags = audioTranscodeFormat?.ytDlpAudioFormat.map { " -x --audio-format \($0)" } ?? ""
        let extraFlags = extraArguments.isEmpty ? "" : " " + extraArguments.joined(separator: " ")
        let target = title ?? "playlist items"
        return "yt-dlp -f \(format)\(playlistFlag)\(subtitleFlags)\(cookiesFlags)\(transcodeFlags)\(extraFlags) -o \"\(outputDir.lastPathComponent)/%(title)s [%(resolution)s].%(ext)s\" …  # \(target)"
    }

    private func formatDiskBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576
        if mb >= 1 {
            return String(format: "%.1f MB", mb)
        }
        return "\(bytes) bytes"
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

    private func parseExtraYtDlpArgumentsOrThrow() throws -> [String] {
        let raw = extraYtDlpArguments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }
        return try parseShellLikeArguments(raw)
    }

    func wholePlaylistSubtitleTrackOrThrow() throws -> SubtitleTrack? {
        guard isWholePlaylistDownload else { return nil }
        guard playlistSubtitleMode != .none else { return nil }

        let lang = playlistSubtitleLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lang.isEmpty else {
            throw AppError(
                message: "Playlist subtitle language is required.",
                recoverySuggestion: "Enter a subtitle language code, for example en or zh-Hans."
            )
        }
        return SubtitleTrack(
            lang: lang,
            label: lang,
            isAuto: playlistSubtitleMode == .auto
        )
    }

    func wholePlaylistArgumentsOrThrow() throws -> [String] {
        guard isWholePlaylistDownload else { return [] }
        guard playlistSegmentMode == .fixedRange else { return [] }

        let raw = playlistSegmentRange.trimmingCharacters(in: .whitespacesAndNewlines)
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
    }

    struct PerItemFormatSelection {
        let index: Int
        let formatSelector: String
    }

    func parsePerItemFormatSelectionsOrThrow() throws -> [PerItemFormatSelection] {
        guard isWholePlaylistDownload, playlistFormatMode == .perItemMapping else { return [] }

        let raw = playlistPerItemFormatMap.trimmingCharacters(in: .whitespacesAndNewlines)
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
