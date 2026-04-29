import Foundation

enum ServiceLogKind: Sendable {
    case command
    case stdout
    case stderr
    case lifecycle
}

struct YtDlpProbeService: Sendable {
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
        extraArguments: [String] = [],
        onLog: @escaping @Sendable (ServiceLogKind, String) -> Void = { _, _ in }
    ) async throws -> MediaInfo {
        let ytDlp = try locator.locate(.ytDlp)

        let config = ProcessConfiguration(
            executableURL: ytDlp,
            arguments: buildProbeArguments(
                url: url,
                cookiesFilePath: cookiesFilePath,
                extraArguments: extraArguments
            )
        )
        onLog(.command, config.commandLine.joined(separator: " "))

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
}
