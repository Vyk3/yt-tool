import Foundation

enum BundledTool: String, CaseIterable {
    case ytDlp = "yt-dlp"
    case ffmpeg = "ffmpeg"
    case ffprobe = "ffprobe"
    case probeFixture = "probe-fixture"
}

struct BundledToolLocator: @unchecked Sendable {
    var bundle: Bundle
    var fileManager: FileManager = .default

    init(bundle: Bundle = .main, fileManager: FileManager = .default) {
        self.bundle = bundle
        self.fileManager = fileManager
    }

    func locate(_ tool: BundledTool) throws -> URL {
        let candidates = candidateURLs(for: tool)
        for candidate in candidates {
            guard fileManager.fileExists(atPath: candidate.path) else {
                continue
            }
            return try validateExecutable(at: candidate, tool: tool)
        }

        throw AppError(
            message: "Bundled tool missing: \(tool.rawValue)",
            recoverySuggestion: "Expected \(tool.rawValue) inside Resources/Binaries."
        )
    }

    func candidateURLs(for tool: BundledTool) -> [URL] {
        let resourceRoot = bundle.resourceURL
        let bundleCandidate = resourceRoot?.appending(path: "Binaries/\(tool.rawValue)", directoryHint: .notDirectory)
        let projectCandidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Resources/Binaries/\(tool.rawValue)", directoryHint: .notDirectory)

        return [bundleCandidate, projectCandidate].compactMap { $0 }
    }

    private func validateExecutable(at url: URL, tool: BundledTool) throws -> URL {
        guard fileManager.isExecutableFile(atPath: url.path) else {
            throw AppError(
                message: "Bundled tool is not executable: \(tool.rawValue)",
                recoverySuggestion: "Check copied file permissions in Resources/Binaries."
            )
        }
        return url
    }
}
