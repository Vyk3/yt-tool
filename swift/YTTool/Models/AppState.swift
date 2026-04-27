import Foundation
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    private enum StorageKey {
        static let selectedOutputDirectoryPath = "selectedOutputDirectoryPath"
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
        }
    }
    @Published var playlistVideoQualityStrategy: PlaylistVideoQualityStrategy = .bestCompatibility
    @Published var playlistAudioQualityStrategy: PlaylistAudioQualityStrategy = .moreCompatible

    // MARK: - Format selection
    @Published var selectedVideoFormat: VideoFormat?
    @Published var selectedAudioFormat: AudioFormat?
    @Published var selectedSubtitle: SubtitleTrack?

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
    private var probeAttemptID: Int = 0
    private var downloadAttemptID: Int = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let path = defaults.string(forKey: StorageKey.selectedOutputDirectoryPath),
           !path.isEmpty,
           Self.isUsableDirectory(URL(fileURLWithPath: path)) {
            self.selectedOutputDirectory = URL(fileURLWithPath: path)
        } else {
            self.selectedOutputDirectory = nil
            defaults.removeObject(forKey: StorageKey.selectedOutputDirectoryPath)
        }

        refreshFFmpegWarning()
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
                let info = try await probeService.probe(url: url, onLog: makeServiceLogger(scope: .probe))
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
        guard case .success = probeState,
              (selectedVideoFormat != nil || selectedAudioFormat != nil)
        else { return false }
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
            guard case .success(let probedInfo) = probeState else { return }
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
        let subtitleTrack = isWholePlaylistDownload ? nil : selectedSubtitle

        let preview = buildCommandPreview(
            title: info?.title,
            videoId: videoId,
            audioId: audioId,
            subtitleTrack: subtitleTrack,
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
        appendLog(scope: .download, level: .info, message: preview)
        downloadState = .preparing(commandPreview: preview)

        let service = YtDlpDownloadService(runner: downloadRunner)

        downloadTask = Task {
            do {
                for try await event in service.download(
                    url: url,
                    videoFormatId: videoId,
                    audioFormatId: audioId,
                    subtitleTrack: subtitleTrack,
                    outputDirectory: outputDir,
                    playlistMode: playlistMode,
                    playlistVideoQualityStrategy: playlistVideoQualityStrategy,
                    playlistAudioQualityStrategy: playlistAudioQualityStrategy,
                    onLog: makeServiceLogger(scope: .download)
                ) {
                    switch event {
                    case .progress(let progress):
                        await MainActor.run {
                            guard isCurrentDownloadAttempt(attemptID) else { return }
                            downloadState = .downloading(progress)
                        }
                    case .completed(let result):
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

    // MARK: - Helpers

    // Call once from the main view's onAppear.
    // Note: ad-hoc signed builds may not register with the notification center —
    // use an Xcode dev build or Developer ID signing to test notifications.
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
            let level: AppLogLevel
            switch kind {
            case .command, .lifecycle, .stdout:
                level = .info
            case .stderr:
                level = .warning
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
            || haystack.contains("disk full") {
            return AppError(
                message: "Insufficient disk space.",
                recoverySuggestion: "Free up disk space or choose another output folder, then try again."
            )
        }

        return error
    }

    private func ffmpegWarningMessage(for missingTools: [BundledTool]) -> String {
        let detail: String
        switch Set(missingTools) {
        case [.ffmpeg]:
            detail = "ffmpeg is missing."
        case [.ffprobe]:
            detail = "ffprobe is missing."
        default:
            detail = "ffmpeg and ffprobe are missing."
        }

        return "\(detail)\nVideo and audio streams may fail to merge.\nReinstall development binaries or rebuild the app bundle."
    }

    private func buildCommandPreview(
        title: String?,
        videoId: String?,
        audioId: String?,
        subtitleTrack: SubtitleTrack?,
        playlistMode: PlaylistMode,
        playlistVideoQualityStrategy: PlaylistVideoQualityStrategy,
        playlistAudioQualityStrategy: PlaylistAudioQualityStrategy,
        outputDir: URL
    ) -> String {
        let format: String
        switch playlistMode {
        case .onlyFirstItem:
            switch (videoId, audioId) {
            case let (v?, a?): format = "\(v)+\(a)"
            case let (v?, nil): format = v
            case let (nil, a?): format = a
            case (nil, nil): format = "best"
            }
        case .wholePlaylistBestVideo:
            switch playlistVideoQualityStrategy {
            case .bestCompatibility:
                format = "bestvideo+bestaudio/best"
            case .preferHigherQuality:
                format = "bv*+ba/b"
            }
        case .wholePlaylistBestAudio:
            switch playlistAudioQualityStrategy {
            case .moreCompatible:
                format = "ba/bestaudio/best"
            case .higherQuality:
                format = "bestaudio/best"
            }
        }
        let playlistFlag = playlistMode.downloadsWholePlaylist ? "" : " --no-playlist"
        var subtitleFlags = ""
        if let subtitleTrack {
            let flag = subtitleTrack.isAuto ? "--write-auto-subs" : "--write-subs"
            subtitleFlags = " \(flag) --sub-langs \(subtitleTrack.lang)"
        }
        let target = title ?? "playlist items"
        return "yt-dlp -f \(format)\(playlistFlag)\(subtitleFlags) -o \"\(outputDir.lastPathComponent)/%(title)s.%(ext)s\" …  # \(target)"
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
}
