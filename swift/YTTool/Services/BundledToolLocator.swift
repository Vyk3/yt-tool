import Foundation

enum BundledTool: String, CaseIterable {
    case ytDlp = "yt-dlp"
    case ffmpeg
    case ffprobe
    case probeFixture = "probe-fixture"
}

struct BundledToolLocator: @unchecked Sendable {
    var bundle: Bundle
    var fileManager: FileManager = .default
    var overrides: [BundledTool: URL] = [:]

    static let userLocalBinariesDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("YTTool", isDirectory: true)
        .appendingPathComponent("Binaries", isDirectory: true)

    static func userLocalURL(for tool: BundledTool) -> URL {
        userLocalBinariesDirectory.appendingPathComponent(tool.rawValue, isDirectory: false)
    }

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
        var candidates: [URL] = []

        if tool == .ytDlp {
            candidates.append(Self.userLocalURL(for: tool))
        }

        if let bundleCandidate = bundle.resourceURL?
            .appending(path: "Binaries/\(tool.rawValue)", directoryHint: .notDirectory)
        {
            candidates.append(bundleCandidate)
        }

        if shouldIncludeProjectFallback {
            let projectCandidate = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Resources/Binaries/\(tool.rawValue)", directoryHint: .notDirectory)
            candidates.append(projectCandidate)
        }

        return candidates
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
