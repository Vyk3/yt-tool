import Foundation

enum ServiceLogKind {
    case command
    case stdout
    case stderr
    case lifecycle
    case warning

    var appLogLevel: AppLogLevel {
        switch self {
        case .command, .lifecycle, .stdout: .info
        case .stderr, .warning: .warning
        }
    }
}

struct YtDlpProbeService {
    var locator: BundledToolLocator
    var runner: ProcessRunner

    init(
        locator: BundledToolLocator = BundledToolLocator(),
        runner: ProcessRunner = ProcessRunner()
    ) {
        self.locator = locator
        self.runner = runner
    }

    func probe(
        url: String,
        cookiesFilePath: String? = nil,
        extraOptions: [ParsedExtraOption] = [],
        onLog: @escaping @Sendable (ServiceLogKind, String) -> Void = { _, _ in }
    ) async throws -> MediaInfo {
        let ytDlp = try locator.locate(.ytDlp)

        let config = ProcessConfiguration(
            executableURL: ytDlp,
            arguments: buildProbeArguments(
                url: url,
                cookiesFilePath: cookiesFilePath,
                extraOptions: extraOptions
            )
        )
        onLog(.command, config.redactedCommandLine.joined(separator: " "))

        let result = try await runner.run(config)
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderrLines = result.stderr
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        stderrLines.prefix(8).forEach { onLog(.stderr, $0) }
        let stderrHint = stderrLines.first
        if stdout == "null" {
            onLog(.stdout, "null")
        } else if !stdout.isEmpty {
            onLog(.stdout, "Received JSON payload (\(stdout.count) chars)")
        }
        onLog(.lifecycle, "Probe exited with status \(result.exitCode)")

        guard result.exitCode == 0 else {
            throw AppError(
                message: "yt-dlp probe failed.",
                recoverySuggestion: stderrHint ?? "Exit code \(result.exitCode)"
            )
        }

        guard !stdout.isEmpty, stdout != "null", let data = stdout.data(using: .utf8) else {
            throw AppError(
                message: "yt-dlp probe failed.",
                recoverySuggestion: stderrHint ?? "yt-dlp did not return a media JSON object."
            )
        }

        return try ProbeParser().parse(data)
    }

    func probePlaylist(
        url: String,
        cookiesFilePath: String? = nil,
        extraOptions: [ParsedExtraOption] = [],
        onLog: @escaping @Sendable (ServiceLogKind, String) -> Void = { _, _ in }
    ) async throws -> [PlaylistEntry] {
        let ytDlp = try locator.locate(.ytDlp)

        let config = ProcessConfiguration(
            executableURL: ytDlp,
            arguments: buildFlatPlaylistArguments(
                url: url,
                cookiesFilePath: cookiesFilePath,
                extraOptions: extraOptions
            )
        )
        onLog(.command, config.redactedCommandLine.joined(separator: " "))

        let result = try await runner.run(config)
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderrLines = result.stderr
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        stderrLines.prefix(8).forEach { onLog(.stderr, $0) }
        let stderrHint = stderrLines.first
        onLog(.lifecycle, "Flat-playlist probe exited with status \(result.exitCode)")

        guard result.exitCode == 0 else {
            throw AppError(
                message: "yt-dlp playlist probe failed.",
                recoverySuggestion: stderrHint ?? "Exit code \(result.exitCode)"
            )
        }

        guard !stdout.isEmpty, stdout != "null", let data = stdout.data(using: .utf8) else {
            throw AppError(
                message: "yt-dlp playlist probe failed.",
                recoverySuggestion: stderrHint ?? "yt-dlp did not return a playlist JSON object."
            )
        }

        return try ProbeParser().parsePlaylist(data)
    }

    func probePlaylistItem(
        playlistURL: String,
        itemIndex: Int,
        cookiesFilePath: String? = nil,
        extraOptions: [ParsedExtraOption] = [],
        onLog: @escaping @Sendable (ServiceLogKind, String) -> Void = { _, _ in }
    ) async throws -> MediaInfo {
        let ytDlp = try locator.locate(.ytDlp)

        let config = ProcessConfiguration(
            executableURL: ytDlp,
            arguments: buildPlaylistItemProbeArguments(
                url: playlistURL,
                itemIndex: itemIndex,
                cookiesFilePath: cookiesFilePath,
                extraOptions: extraOptions
            )
        )
        onLog(.command, config.redactedCommandLine.joined(separator: " "))

        let result = try await runner.run(config)
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderrLines = result.stderr
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        stderrLines.prefix(8).forEach { onLog(.stderr, $0) }
        let stderrHint = stderrLines.first
        onLog(.lifecycle, "Playlist item \(itemIndex) probe exited with status \(result.exitCode)")

        guard result.exitCode == 0 else {
            throw AppError(
                message: "yt-dlp item probe failed.",
                recoverySuggestion: stderrHint ?? "Exit code \(result.exitCode)"
            )
        }

        guard !stdout.isEmpty, stdout != "null", let data = stdout.data(using: .utf8) else {
            throw AppError(
                message: "yt-dlp item probe failed.",
                recoverySuggestion: stderrHint ?? "yt-dlp did not return a media JSON object."
            )
        }

        return try ProbeParser().parsePlaylistItemProbe(data)
    }
}
