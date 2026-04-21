import Foundation

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

    func probe(url: String) async throws -> MediaInfo {
        let ytDlp = try locator.locate(.ytDlp)

        let config = ProcessConfiguration(
            executableURL: ytDlp,
            arguments: ["--dump-single-json", "--no-playlist", url]
        )

        let result = try await runner.run(config)
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let stderrHint = result.stderr
            .components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })

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
