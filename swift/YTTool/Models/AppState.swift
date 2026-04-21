import Foundation
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    private enum StorageKey {
        static let selectedOutputDirectoryPath = "selectedOutputDirectoryPath"
    }

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

    // MARK: - Private
    private let probeService = YtDlpProbeService()
    private let downloadRunner = ProcessRunner()
    private let defaults: UserDefaults
    private var probeTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let path = defaults.string(forKey: StorageKey.selectedOutputDirectoryPath),
           !path.isEmpty {
            self.selectedOutputDirectory = URL(fileURLWithPath: path)
        } else {
            self.selectedOutputDirectory = nil
        }

        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Probe

    func probe() {
        let url = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        probeTask?.cancel()
        probeState = .loading
        selectedVideoFormat = nil
        selectedAudioFormat = nil
        downloadState = .idle

        probeTask = Task {
            do {
                let info = try await probeService.probe(url: url)
                probeState = .success(info)
            } catch let error as AppError {
                probeState = .failure(error)
            } catch {
                probeState = .failure(AppError(
                    message: "Probe failed.",
                    recoverySuggestion: error.localizedDescription
                ))
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
        downloadState = .preparing(commandPreview: preview)

        let service = YtDlpDownloadService(runner: downloadRunner)

        downloadTask = Task {
            do {
                for try await event in service.download(
                    url: url,
                    videoFormatId: videoId,
                    audioFormatId: audioId,
                    outputDirectory: outputDir
                ) {
                    switch event {
                    case .progress(let progress):
                        downloadState = .downloading(progress)
                    case .completed(let result):
                        downloadState = .succeeded(outputURL: result.outputURL)
                        self.sendCompletionNotification(outputURL: result.outputURL)
                    }
                }
            } catch is CancellationError {
                downloadState = .cancelled
            } catch let error as AppError {
                downloadState = .failed(error)
            } catch {
                downloadState = .failed(AppError(
                    message: "Download failed.",
                    recoverySuggestion: error.localizedDescription
                ))
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        Task { try? await downloadRunner.cancel() }
        downloadState = .cancelled
    }

    // MARK: - Helpers

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
