import Foundation

struct YtDlpReleaseInfo: Equatable {
    let version: String
    let downloadURL: URL
}

struct YtDlpUpdateService {
    /// GitHub release asset name for the cross-platform Python zipapp.
    private static let zipappAssetName = "yt-dlp"

    /// User-local path for the yt-dlp zipapp (the actual Python archive).
    static var userLocalZipappURL: URL {
        BundledToolLocator.userLocalBinariesDirectory
            .appendingPathComponent("yt-dlp-zipapp", isDirectory: false)
    }

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
        guard let asset = release.assets.first(where: { $0.name == zipappAssetName }) else {
            throw AppError(
                message: "Update check failed.",
                recoverySuggestion: "No yt-dlp zipapp found in release \(release.tagName)."
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

        // Verify the zipapp works before placing it.
        let newVersion = try await verifyZipapp(at: tempURL)

        let destinationDir = BundledToolLocator.userLocalBinariesDirectory
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        let wrapperURL = BundledToolLocator.userLocalURL(for: .ytDlp)
        let zipappURL = Self.userLocalZipappURL
        let wrapperBackup = wrapperURL.appendingPathExtension("backup")
        let zipappBackup = zipappURL.appendingPathExtension("backup")

        // Backup + install inside a single do/catch so any failure
        // (including backup failures) triggers a full restore.
        var didBackupWrapper = false
        var didBackupZipapp = false
        do {
            if FileManager.default.fileExists(atPath: wrapperURL.path) {
                try? FileManager.default.removeItem(at: wrapperBackup)
                try FileManager.default.moveItem(at: wrapperURL, to: wrapperBackup)
                didBackupWrapper = true
            }
            if FileManager.default.fileExists(atPath: zipappURL.path) {
                try? FileManager.default.removeItem(at: zipappBackup)
                try FileManager.default.moveItem(at: zipappURL, to: zipappBackup)
                didBackupZipapp = true
            }
            try FileManager.default.moveItem(at: tempURL, to: zipappURL)
            try writeWrapper(at: wrapperURL)
        } catch {
            // Restore on failure (best-effort, swallowed errors logged).
            try? FileManager.default.removeItem(at: zipappURL)
            try? FileManager.default.removeItem(at: wrapperURL)
            if didBackupZipapp {
                try? FileManager.default.moveItem(at: zipappBackup, to: zipappURL)
            }
            if didBackupWrapper {
                try? FileManager.default.moveItem(at: wrapperBackup, to: wrapperURL)
            }
            throw AppError(message: "Failed to install update.", recoverySuggestion: error.localizedDescription)
        }

        try? FileManager.default.removeItem(at: wrapperBackup)
        try? FileManager.default.removeItem(at: zipappBackup)
        return newVersion
    }

    // MARK: - Self-heal

    func validateUserLocalBinary() async -> Bool {
        let wrapperURL = BundledToolLocator.userLocalURL(for: .ytDlp)
        let zipappURL = Self.userLocalZipappURL
        guard FileManager.default.fileExists(atPath: wrapperURL.path) else { return true }
        guard FileManager.default.isExecutableFile(atPath: wrapperURL.path) else { return false }
        guard FileManager.default.fileExists(atPath: zipappURL.path) else { return false }

        let runner = ProcessRunner()
        let config = ProcessConfiguration(executableURL: wrapperURL, arguments: ["--version"])
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
            delegate.session = session
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

    /// Resolve the best available Python interpreter, matching wrapper logic:
    /// prefer the app bundle's embedded Python, fall back to system python3.
    private func resolvePython() -> URL {
        if let bundlePython = Bundle.main.resourceURL?
            .appendingPathComponent("Python/bin/python3.12"),
           FileManager.default.isExecutableFile(atPath: bundlePython.path)
        {
            return bundlePython
        }
        return URL(fileURLWithPath: "/usr/bin/python3")
    }

    /// Verify a downloaded zipapp by running it with the best available Python.
    private func verifyZipapp(at url: URL) async throws -> String {
        let python = resolvePython()
        let runner = ProcessRunner()
        let config = ProcessConfiguration(
            executableURL: python,
            arguments: [url.path, "--version"]
        )
        let result = try await runner.run(config)
        let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0, !version.isEmpty else {
            throw AppError(
                message: "Zipapp verification failed.",
                recoverySuggestion: "The downloaded yt-dlp zipapp did not produce a valid version output. Ensure python3 is available."
            )
        }
        return version
    }

    /// Escape a path for safe embedding in a POSIX single-quoted string.
    /// The only character that needs escaping in single quotes is `'` itself,
    /// which is handled by ending the quote, inserting an escaped `'`, and reopening.
    static func shellEscapeSingleQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Write a wrapper shell script that invokes the zipapp via the best available Python.
    private func writeWrapper(at wrapperURL: URL) throws {
        let pythonInBundle = Bundle.main.resourceURL?
            .appendingPathComponent("Python/bin/python3.12").path ?? ""

        // Use single-quote escaping to prevent shell interpretation of the embedded path.
        let escapedPython = Self.shellEscapeSingleQuoted(pythonInBundle)

        let script = """
        #!/bin/sh
        DIR="$(cd "$(dirname "$0")" && pwd)"
        export PYTHONDONTWRITEBYTECODE=1
        PYTHON=\(escapedPython)
        if [ -x "$PYTHON" ]; then
            exec "$PYTHON" "$DIR/yt-dlp-zipapp" "$@"
        else
            exec python3 "$DIR/yt-dlp-zipapp" "$@"
        fi
        """
        try script.write(to: wrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: wrapperURL.path
        )
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
    var session: URLSession?

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
        session?.finishTasksAndInvalidate()
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
