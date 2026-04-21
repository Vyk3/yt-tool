import Foundation
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    private enum StorageKey {
        static let selectedOutputDirectoryPath = "selectedOutputDirectoryPath"
    }
    private static let maxLogEntries = 250

    // MARK: - Probe
    @Published var inputURL: String = ""
    @Published var probeState: ProbeState = .idle

    // MARK: - Format selection
    @Published var selectedVideoFormat: VideoFormat?
    @Published var selectedAudioFormat: AudioFormat?

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
           !path.isEmpty {
            self.selectedOutputDirectory = URL(fileURLWithPath: path)
        } else {
            self.selectedOutputDirectory = nil
        }

    }

    // MARK: - Probe

    func probe() {
        let url = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        probeTask?.cancel()
        let attemptID = beginProbeAttempt()
        appendLog(scope: .probe, level: .info, message: "Starting probe for \(url)")
        probeState = .loading
        selectedVideoFormat = nil
        selectedAudioFormat = nil
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
        guard case .success = probeState,
              selectedOutputDirectory != nil,
              (selectedVideoFormat != nil || selectedAudioFormat != nil)
        else { return false }
        // Allow re-download after cancel / failure / success — only block while active.
        return !isDownloading
    }

    var isDownloading: Bool {
        if case .downloading = downloadState { return true }
        if case .preparing = downloadState { return true }
        return false
    }

    func download() {
        guard case .success(let info) = probeState,
              let outputDir = selectedOutputDirectory
        else { return }

        downloadTask?.cancel()
        let attemptID = beginDownloadAttempt()
        downloadState = .idle

        let url = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let videoId = selectedVideoFormat?.id
        let audioId = selectedAudioFormat?.id

        let preview = buildCommandPreview(
            title: info.title,
            videoId: videoId,
            audioId: audioId,
            outputDir: outputDir
        )
        appendLog(scope: .download, level: .info, message: "Preparing download for \(info.title)")
        appendLog(scope: .download, level: .info, message: preview)
        downloadState = .preparing(commandPreview: preview)

        let service = YtDlpDownloadService(runner: downloadRunner)

        downloadTask = Task {
            do {
                for try await event in service.download(
                    url: url,
                    videoFormatId: videoId,
                    audioFormatId: audioId,
                    outputDirectory: outputDir,
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
                    downloadState = .failed(error)
                    appendLog(scope: .download, level: .error, message: joinedErrorMessage(error))
                }
            } catch {
                await MainActor.run {
                    guard isCurrentDownloadAttempt(attemptID) else { return }
                    downloadTask = nil
                    downloadState = .failed(AppError(
                        message: "Download failed.",
                        recoverySuggestion: error.localizedDescription
                    ))
                    appendLog(scope: .download, level: .error, message: "Download failed. \(error.localizedDescription)")
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

    private func buildCommandPreview(
        title: String,
        videoId: String?,
        audioId: String?,
        outputDir: URL
    ) -> String {
        let format: String
        switch (videoId, audioId) {
        case let (v?, a?): format = "\(v)+\(a)"
        case let (v?, nil): format = v
        case let (nil, a?): format = a
        case (nil, nil): format = "best"
        }
        return "yt-dlp -f \(format) -o \"\(outputDir.lastPathComponent)/%(title)s.%(ext)s\" …"
    }
}
