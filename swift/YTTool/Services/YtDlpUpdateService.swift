import Foundation

struct YtDlpReleaseInfo: Equatable {
    let version: String
    let downloadURL: URL
}

struct YtDlpUpdateService {
    private static let macOSAssetName = "yt-dlp_macos"

    private var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return "YTTool/\(version)"
    }

    // MARK: - Version check

    func currentVersion(locator: BundledToolLocator = BundledToolLocator()) async -> String? {
        guard let ytDlpURL = try? locator.locate(.ytDlp) else { return nil }
        let runner = ProcessRunner()
        let config = ProcessConfiguration(
            executableURL: ytDlpURL,
            arguments: ["--version"]
        )
        guard let result = try? await runner.run(config),
              result.exitCode == 0
        else { return nil }
        let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : version
    }

    // MARK: - Fetch latest release

    func fetchLatestRelease(channel: UpdateChannel) async throws -> YtDlpReleaseInfo {
        var request = URLRequest(url: channel.apiURL)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError(message: "Update check failed.", recoverySuggestion: "Unexpected response type.")
        }
        guard http.statusCode == 200 else {
            throw AppError(
                message: "Update check failed.",
                recoverySuggestion: "GitHub API returned HTTP \(http.statusCode)."
            )
        }

        return try Self.parseRelease(from: data)
    }

    static func parseRelease(from data: Data) throws -> YtDlpReleaseInfo {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let asset = release.assets.first(where: { $0.name == macOSAssetName }) else {
            throw AppError(
                message: "Update check failed.",
                recoverySuggestion: "No macOS binary found in release \(release.tagName)."
            )
        }
        guard let downloadURL = URL(string: asset.browserDownloadURL) else {
            throw AppError(message: "Update check failed.", recoverySuggestion: "Invalid download URL.")
        }
        return YtDlpReleaseInfo(version: release.tagName, downloadURL: downloadURL)
    }

    // MARK: - Install

    func install(
        from release: YtDlpReleaseInfo,
        onProgress: @escaping @Sendable (Double) -> Void,
        onVerifying: @escaping @Sendable () -> Void
    ) async throws -> String {
        let tempURL = try await downloadBinary(from: release.downloadURL, onProgress: onProgress)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        onVerifying()

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: tempURL.path
        )

        await clearQuarantine(at: tempURL)
        try await codesign(binaryAt: tempURL)

        let newVersion = try await verifyBinary(at: tempURL)

        let destinationDir = BundledToolLocator.userLocalBinariesDirectory
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        let destinationURL = BundledToolLocator.userLocalURL(for: .ytDlp)
        let backupURL = destinationURL.appendingPathExtension("backup")

        var didBackup = false
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.moveItem(at: destinationURL, to: backupURL)
            didBackup = true
        }

        do {
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        } catch {
            if didBackup {
                do {
                    try FileManager.default.moveItem(at: backupURL, to: destinationURL)
                } catch let restoreError {
                    throw AppError(
                        message: "Failed to install update and could not restore previous version.",
                        recoverySuggestion: "Install: \(error.localizedDescription) Restore: \(restoreError.localizedDescription)"
                    )
                }
            }
            throw AppError(message: "Failed to install update.", recoverySuggestion: error.localizedDescription)
        }

        try? FileManager.default.removeItem(at: backupURL)
        return newVersion
    }

    // MARK: - Self-heal

    func validateUserLocalBinary() async -> Bool {
        let url = BundledToolLocator.userLocalURL(for: .ytDlp)
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        guard FileManager.default.isExecutableFile(atPath: url.path) else { return false }

        let runner = ProcessRunner()
        let config = ProcessConfiguration(executableURL: url, arguments: ["--version"])
        guard let result = try? await runner.run(config),
              result.exitCode == 0,
              !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }

        return true
    }

    // MARK: - Private

    private func downloadBinary(
        from url: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadProgressDelegate(
                onProgress: onProgress,
                onComplete: { result in continuation.resume(with: result) }
            )
            let session = URLSession(
                configuration: .default,
                delegate: delegate,
                delegateQueue: nil
            )
            var request = URLRequest(url: url)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            session.downloadTask(with: request).resume()
        }
    }

    private func clearQuarantine(at url: URL) async {
        let runner = ProcessRunner()
        let config = ProcessConfiguration(
            executableURL: URL(fileURLWithPath: "/usr/bin/xattr"),
            arguments: ["-cr", url.path]
        )
        _ = try? await runner.run(config)
    }

    private func codesign(binaryAt url: URL) async throws {
        let runner = ProcessRunner()
        let config = ProcessConfiguration(
            executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["--force", "--sign", "-", url.path]
        )
        let result = try await runner.run(config)
        guard result.exitCode == 0 else {
            throw AppError(
                message: "Code signing failed.",
                recoverySuggestion: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private func verifyBinary(at url: URL) async throws -> String {
        let runner = ProcessRunner()
        let config = ProcessConfiguration(executableURL: url, arguments: ["--version"])
        let result = try await runner.run(config)
        let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0, !version.isEmpty else {
            throw AppError(
                message: "Binary verification failed.",
                recoverySuggestion: "The downloaded yt-dlp binary did not produce a valid version output."
            )
        }
        return version
    }
}

// MARK: - GitHub API types

struct GitHubRelease: Codable {
    let tagName: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

// MARK: - Download delegate

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private let onComplete: @Sendable (Result<URL, Error>) -> Void
    private var completed = false
    private let lock = NSLock()

    init(
        onProgress: @escaping @Sendable (Double) -> Void,
        onComplete: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    private func completeOnce(with result: Result<URL, Error>) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()
        onComplete(result)
    }

    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        do {
            try FileManager.default.moveItem(at: location, to: tempURL)
            completeOnce(with: .success(tempURL))
        } catch {
            completeOnce(with: .failure(error))
        }
    }

    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            completeOnce(with: .failure(error))
        }
    }
}
