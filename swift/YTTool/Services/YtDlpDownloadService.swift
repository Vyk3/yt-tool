import Foundation

/// Encapsulates a completed download result.
struct DownloadResult {
    var outputURL: URL
}

/// Streams download progress from yt-dlp and signals completion or failure.
///
/// Events emitted:
///   - `.progress(DownloadProgress)` — parsed progress updates from stderr
///   - `.completed(DownloadResult)` — when yt-dlp exits with code 0
enum DownloadEvent {
    case progress(DownloadProgress)
    case completed(DownloadResult)
}

struct YtDlpDownloadService: Sendable {
    var locator: BundledToolLocator
    var runner: ProcessRunner

    init(
        locator: BundledToolLocator = BundledToolLocator(),
        runner: ProcessRunner = ProcessRunner()
    ) {
        self.locator = locator
        self.runner = runner
    }

    /// Streams download events for the given URL and format selection.
    ///
    /// - Parameters:
    ///   - url: The webpage URL to download from.
    ///   - videoFormatId: ID of the selected video format (nil for audio-only).
    ///   - audioFormatId: ID of the selected audio format (nil for video-only or muxed).
    ///   - outputDirectory: The directory to save the downloaded file.
    func download(
        url: String,
        videoFormatId: String?,
        audioFormatId: String?,
        outputDirectory: URL
    ) -> AsyncThrowingStream<DownloadEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let ytDlp = try locator.locate(.ytDlp)

                    let formatSelector = buildFormatSelector(
                        videoId: videoFormatId,
                        audioId: audioFormatId
                    )
                    let outputTemplate = outputDirectory
                        .appendingPathComponent("%(title)s.%(ext)s")
                        .path(percentEncoded: false)

                    let config = ProcessConfiguration(
                        executableURL: ytDlp,
                        arguments: [
                            "-f", formatSelector,
                            "-o", outputTemplate,
                            "--progress",
                            "--newline",
                            "--no-playlist",
                            url,
                        ],
                        terminationGracePeriod: .seconds(3)
                    )

                    let parser = ProgressParser()
                    var lastResult: ProcessResult?

                    for try await event in runner.stream(config) {
                        switch event {
                        case .stderr(let chunk):
                            if let progress = parser.parse(chunk: chunk) {
                                continuation.yield(.progress(progress))
                            }
                        case .finished(let result):
                            lastResult = result
                        case .stdout, .started:
                            break
                        }
                    }

                    guard let result = lastResult else {
                        throw AppError(
                            message: "Download ended unexpectedly.",
                            recoverySuggestion: "The process terminated without a result."
                        )
                    }

                    guard result.exitCode == 0 else {
                        let hint = result.stderr
                            .components(separatedBy: "\n")
                            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                            .last(where: { !$0.hasPrefix("[download]") })
                            ?? "Exit code \(result.exitCode)"
                        throw AppError(
                            message: "Download failed.",
                            recoverySuggestion: hint
                        )
                    }

                    // Best-effort: find the output file by scanning the directory.
                    let outputURL = resolveOutputFile(in: outputDirectory)
                    continuation.yield(.completed(DownloadResult(outputURL: outputURL ?? outputDirectory)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func cancel() async {
        try? await runner.cancel()
    }

    // MARK: - Helpers

    private func buildFormatSelector(videoId: String?, audioId: String?) -> String {
        switch (videoId, audioId) {
        case let (v?, a?):
            return "\(v)+\(a)"
        case let (v?, nil):
            return v
        case let (nil, a?):
            return a
        case (nil, nil):
            return "bestvideo+bestaudio/best"
        }
    }

    /// Heuristic: find the most recently modified file in `directory` added
    /// in the last 30 seconds. Falls back to directory URL if nothing is found.
    private func resolveOutputFile(in directory: URL) -> URL? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return nil }

        let cutoff = Date().addingTimeInterval(-30)
        return contents
            .compactMap { url -> (URL, Date)? in
                guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                else { return nil }
                return date > cutoff ? (url, date) : nil
            }
            .max(by: { $0.1 < $1.1 })?
            .0
    }
}
