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

        guard result.exitCode == 0 else {
            let hint = result.stderr
                .components(separatedBy: "\n")
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                ?? "Exit code \(result.exitCode)"
            throw AppError(
                message: "yt-dlp probe failed.",
                recoverySuggestion: hint
            )
        }

        guard let data = result.stdout.data(using: .utf8), !data.isEmpty else {
            throw AppError(
                message: "yt-dlp returned no output.",
                recoverySuggestion: "Check the URL and try again."
            )
        }

        return try ProbeParser().parse(data)
    }
}
