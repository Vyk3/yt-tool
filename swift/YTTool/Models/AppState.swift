import Foundation

@MainActor
final class AppState: ObservableObject {
    // MARK: - Probe
    @Published var inputURL: String = ""
    @Published var probeState: ProbeState = .idle
    @Published var userFacingError: AppError?

    // MARK: - Format selection
    @Published var selectedVideoFormat: VideoFormat?
    @Published var selectedAudioFormat: AudioFormat?

    // MARK: - Output directory
    @Published var selectedOutputDirectory: URL?

    // MARK: - Download
    @Published var downloadState: DownloadState = .idle

    // MARK: - Private
    private let probeService = YtDlpProbeService()
    private let downloadRunner = ProcessRunner()
    private var probeTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?

    // MARK: - Probe

    func probe() {
        let url = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        probeTask?.cancel()
        probeState = .loading
        userFacingError = nil
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
              (selectedVideoFormat != nil || selectedAudioFormat != nil),
              case .idle = downloadState
        else { return false }
        return true
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
