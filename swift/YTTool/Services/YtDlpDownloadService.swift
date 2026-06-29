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

/// Builds a yt-dlp format selector string from the given parameters.
///
/// Shared between `YtDlpDownloadService` (actual download) and `AppState` (command preview).
func buildFormatSelector(
    videoId: String?,
    audioId: String?,
    playlistMode: PlaylistMode,
    playlistVideoQualityStrategy: PlaylistVideoQualityStrategy,
    playlistAudioQualityStrategy: PlaylistAudioQualityStrategy
) -> String {
    switch playlistMode {
    case .onlyFirstItem:
        switch (videoId, audioId) {
        case let (v?, a?):
            "\(v)+\(a)"
        case let (v?, nil):
            v
        case let (nil, a?):
            a
        case (nil, nil):
            "bestvideo+bestaudio/best"
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
}

struct YtDlpDownloadService {
    var locator: BundledToolLocator
    var runner: any ProcessRunning

    init(
        locator: BundledToolLocator = BundledToolLocator(),
        runner: any ProcessRunning = ProcessRunner()
    ) {
        self.locator = locator
        self.runner = runner
    }

    func download(
        plan: ResolvedDownloadPlan,
        onLog: @escaping @Sendable (ServiceLogKind, String) -> Void = { _, _ in }
    ) -> AsyncThrowingStream<DownloadEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let ytDlp = try locator.locate(.ytDlp)
                    let ffmpeg = try locator.locate(.ffmpeg)

                    let renderedExtra = renderExtraOptions(plan.extraOptions, for: .download)
                    let allExtraArgv = renderedExtra + plan.managedArguments
                    let hasDownloadSections = allExtraArgv.contains("--download-sections")

                    if hasDownloadSections {
                        if plan.selectedProtocols.isEmpty {
                            onLog(.warning, "download-sections without format metadata: relying on compiled protocol restriction")
                        } else {
                            for proto in plan.selectedProtocols {
                                let result = ProtocolChecker.check(transportProtocol: proto)
                                if case let .rejected(reason) = result {
                                    throw AppError(
                                        message: "Protocol rejected for remote FFmpeg path.",
                                        recoverySuggestion: reason
                                    )
                                }
                            }
                        }
                    }

                    let config = ProcessConfiguration(
                        executableURL: ytDlp,
                        arguments: buildDownloadArguments(
                            plan: plan,
                            ffmpegLocation: ffmpeg.path(percentEncoded: false)
                        ),
                        terminationGracePeriod: .seconds(3)
                    )
                    onLog(.command, config.redactedCommandLine.joined(separator: " "))

                    // Keep one parser per output stream so chunk buffering stays
                    // correct even when yt-dlp sends progress to stdout instead of stderr.
                    var stdoutProgressParser = ProgressParser()
                    var stderrProgressParser = ProgressParser()
                    var lastResult: ProcessResult?
                    for try await event in runner.stream(config) {
                        switch event {
                        case let .stdout(chunk):
                            if let progress = stdoutProgressParser.consume(
                                chunk: chunk,
                                onNonProgressLine: { line in onLog(.stdout, line) }
                            ) {
                                continuation.yield(.progress(progress))
                            }
                        case let .stderr(chunk):
                            if let progress = stderrProgressParser.consume(
                                chunk: chunk,
                                onNonProgressLine: { line in onLog(.stderr, line) }
                            ) {
                                continuation.yield(.progress(progress))
                            }
                        case let .finished(result):
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

                    let outputURL: URL = if plan.returnsOutputDirectoryOnSuccess {
                        plan.outputDirectory
                    } else {
                        result.stdout
                            .components(separatedBy: "\n")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .compactMap { URL(filePath: $0) }
                            .last(where: { FileManager.default.fileExists(atPath: $0.path) })
                            ?? plan.outputDirectory
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
        formatSelectorOverride: String? = nil,
        includeNoPlaylistOverride: Bool? = nil,
        audioTranscodeFormat: AudioTranscodeFormat? = nil,
        cookiesFilePath: String? = nil,
        extraOptions: [ParsedExtraOption] = [],
        managedArguments: [String] = [],
        selectedProtocols: [String?] = [],
        subtitleTrack: SubtitleTrack? = nil,
        outputDirectory: URL,
        playlistMode: PlaylistMode = .onlyFirstItem,
        playlistVideoQualityStrategy: PlaylistVideoQualityStrategy = .bestCompatibility,
        playlistAudioQualityStrategy: PlaylistAudioQualityStrategy = .moreCompatible,
        aria2cPath: String? = nil,
        onLog: @escaping @Sendable (ServiceLogKind, String) -> Void = { _, _ in }
    ) -> AsyncThrowingStream<DownloadEvent, Error> {
        let plan = ResolvedDownloadPlan(
            url: url,
            formatSelector: formatSelectorOverride ?? YTTool.buildFormatSelector(
                videoId: videoFormatId,
                audioId: audioFormatId,
                playlistMode: playlistMode,
                playlistVideoQualityStrategy: playlistVideoQualityStrategy,
                playlistAudioQualityStrategy: playlistAudioQualityStrategy
            ),
            includeNoPlaylist: includeNoPlaylistOverride ?? (playlistMode == .onlyFirstItem),
            audioTranscodeFormat: audioTranscodeFormat,
            cookiesFilePath: cookiesFilePath,
            extraOptions: extraOptions,
            managedArguments: managedArguments,
            selectedProtocols: selectedProtocols,
            subtitleTrack: subtitleTrack,
            outputDirectory: outputDirectory,
            aria2cPath: aria2cPath,
            previewTarget: "download target",
            returnsOutputDirectoryOnSuccess: playlistMode.downloadsWholePlaylist && includeNoPlaylistOverride == nil
        )
        return download(plan: plan, onLog: onLog)
    }

    func cancel() async {
        try? await runner.cancel()
    }
}
