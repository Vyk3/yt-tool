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
    var overrides: [BundledTool: URL] = [:]

    init(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        overrides: [BundledTool: URL] = [:]
    ) {
        self.bundle = bundle
        self.fileManager = fileManager
        self.overrides = overrides
    }

    func locate(_ tool: BundledTool) throws -> URL {
        if let override = overrides[tool] {
            return try validateExecutable(at: override, tool: tool)
        }

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

    func missingTools(_ tools: [BundledTool]) -> [BundledTool] {
        tools.filter { tool in
            (try? locate(tool)) == nil
        }
    }

    func candidateURLs(for tool: BundledTool) -> [URL] {
        let resourceRoot = bundle.resourceURL
        let bundleCandidate = resourceRoot?.appending(path: "Binaries/\(tool.rawValue)", directoryHint: .notDirectory)
        guard shouldIncludeProjectFallback else {
            return [bundleCandidate].compactMap { $0 }
        }

        let projectCandidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Resources/Binaries/\(tool.rawValue)", directoryHint: .notDirectory)
        return [bundleCandidate, projectCandidate].compactMap { $0 }
    }

    private var shouldIncludeProjectFallback: Bool {
        bundle.bundleURL.pathExtension != "app"
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
