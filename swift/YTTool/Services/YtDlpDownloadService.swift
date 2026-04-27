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
        outputDirectory: URL,
        playlistMode: PlaylistMode = .onlyFirstItem,
        playlistVideoQualityStrategy: PlaylistVideoQualityStrategy = .bestCompatibility,
        onLog: @escaping @Sendable (ServiceLogKind, String) -> Void = { _, _ in }
    ) -> AsyncThrowingStream<DownloadEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let ytDlp = try locator.locate(.ytDlp)
                    // P1 fix: always pass the bundled ffmpeg so muxing works on
                    // machines where ffmpeg is not installed in PATH.
                    let ffmpeg = try locator.locate(.ffmpeg)

                    let formatSelector = buildFormatSelector(
                        videoId: videoFormatId,
                        audioId: audioFormatId,
                        playlistMode: playlistMode,
                        playlistVideoQualityStrategy: playlistVideoQualityStrategy
                    )
                    let outputTemplate = outputDirectory
                        .appendingPathComponent("%(title)s.%(ext)s")
                        .path(percentEncoded: false)

                    var arguments = [
                        "-f", formatSelector,
                        "-o", outputTemplate,
                        // P1 fix: point yt-dlp at the vendored ffmpeg binary.
                        "--ffmpeg-location", ffmpeg.deletingLastPathComponent().path,
                        // P3 fix: ask yt-dlp to print the actual final file path
                        // to stdout after post-processing, so we don't have to
                        // guess from directory mtime.
                        "--print", "after_move:filepath",
                        "--progress",
                        "--newline",
                    ]
                    if playlistMode == .onlyFirstItem {
                        arguments.append("--no-playlist")
                    }
                    arguments.append(url)

                    let config = ProcessConfiguration(
                        executableURL: ytDlp,
                        arguments: arguments,
                        terminationGracePeriod: .seconds(3)
                    )
                    onLog(.command, config.commandLine.joined(separator: " "))

                    // Keep one parser per output stream so chunk buffering stays
                    // correct even when yt-dlp sends progress to stdout instead of stderr.
                    var stdoutProgressParser = ProgressParser()
                    var stderrProgressParser = ProgressParser()
                    var lastResult: ProcessResult?
                    for try await event in runner.stream(config) {
                        switch event {
                        case .stdout(let chunk):
                            if let progress = stdoutProgressParser.consume(
                                chunk: chunk,
                                onNonProgressLine: { line in onLog(.stdout, line) }
                            ) {
                                continuation.yield(.progress(progress))
                            }
                        case .stderr(let chunk):
                            if let progress = stderrProgressParser.consume(
                                chunk: chunk,
                                onNonProgressLine: { line in onLog(.stderr, line) }
                            ) {
                                continuation.yield(.progress(progress))
                            }
                        case .finished(let result):
                            lastResult = result
                        case .started:
                            break
                        }
                    }

                    guard let result = lastResult else {
                        onLog(.lifecycle, "Download ended without a final process result")
                        throw AppError(
                            message: "Download ended unexpectedly.",
                            recoverySuggestion: "The process terminated without a result."
                        )
                    }
                    onLog(.lifecycle, "Download exited with status \(result.exitCode)")

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

                    // P3 fix: use the filepath printed by --print after_move:filepath.
                    // Fall back to the output directory if yt-dlp didn't emit one
                    // (e.g. older yt-dlp version or no post-processing step).
                    let outputURL: URL
                    if playlistMode.downloadsWholePlaylist {
                        outputURL = outputDirectory
                    } else {
                        outputURL = result.stdout
                            .components(separatedBy: "\n")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .compactMap { URL(filePath: $0) }
                            .last(where: { FileManager.default.fileExists(atPath: $0.path) })
                            ?? outputDirectory
                    }
                    onLog(.lifecycle, "Resolved output path: \(outputURL.path(percentEncoded: false))")
                    continuation.yield(.completed(DownloadResult(outputURL: outputURL)))
                    continuation.finish()
                } catch {
                    onLog(.lifecycle, "Download stream threw: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func cancel() async {
        try? await runner.cancel()
    }

    // MARK: - Helpers

    private func buildFormatSelector(
        videoId: String?,
        audioId: String?,
        playlistMode: PlaylistMode,
        playlistVideoQualityStrategy: PlaylistVideoQualityStrategy
    ) -> String {
        switch playlistMode {
        case .onlyFirstItem:
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
        case .wholePlaylistBestVideo:
            switch playlistVideoQualityStrategy {
            case .bestCompatibility:
                return "bestvideo+bestaudio/best"
            case .preferHigherQuality:
                return "bv*+ba/b"
            }
        case .wholePlaylistBestAudio:
            return "ba/bestaudio/best"
        }
    }
}
