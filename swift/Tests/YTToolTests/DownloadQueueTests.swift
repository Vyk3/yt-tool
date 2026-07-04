import XCTest
@testable import YTTool

@MainActor
final class DownloadQueueTests: XCTestCase {
    private func makeConfig(
        outputDirectory: URL = URL(fileURLWithPath: "/tmp"),
        audioTranscodeFormat: AudioTranscodeFormat = .original,
        downloaderPreference: DownloaderPreference = .native,
        aria2cPath: String? = nil
    ) -> QueueItemConfig {
        QueueItemConfig(
            outputDirectory: outputDirectory,
            cookiesFilePath: nil,
            extraOptions: [],
            audioTranscodeFormat: audioTranscodeFormat,
            downloaderPreference: downloaderPreference,
            aria2cPath: aria2cPath,
            qualityStrategy: .bestQuality
        )
    }

    // MARK: - Add

    func testAddURLsCreatesItems() {
        let queue = DownloadQueue()
        queue.addURLs(["https://example.com/a", "https://example.com/b"], config: makeConfig())
        XCTAssertEqual(queue.items.count, 2)
        XCTAssertEqual(queue.items[0].url, "https://example.com/a")
        XCTAssertEqual(queue.items[1].url, "https://example.com/b")
    }

    func testAddURLsFiltersEmptyStrings() {
        let queue = DownloadQueue()
        queue.addURLs(["https://example.com/a", "", "  ", "https://example.com/b"], config: makeConfig())
        XCTAssertEqual(queue.items.count, 2)
    }

    func testAddURLsTrimsWhitespace() {
        let queue = DownloadQueue()
        queue.addURLs(["  https://example.com/a  "], config: makeConfig())
        XCTAssertEqual(queue.items[0].url, "https://example.com/a")
    }

    // MARK: - Remove

    func testRemoveItem() {
        let queue = DownloadQueue()
        queue.addURLs(["https://example.com/a", "https://example.com/b"], config: makeConfig())
        let item = queue.items[0]
        queue.removeItem(item)
        XCTAssertEqual(queue.items.count, 1)
        XCTAssertEqual(queue.items[0].url, "https://example.com/b")
    }

    // MARK: - Cancel

    func testCancelPendingItem() {
        let queue = DownloadQueue()
        queue.addURLs(["https://example.com/a"], config: makeConfig())
        queue.cancelItem(queue.items[0])
        XCTAssertEqual(queue.items[0].status, .cancelled)
    }

    func testCancelTerminalItemIsNoOp() {
        let queue = DownloadQueue()
        queue.addURLs(["https://example.com/a"], config: makeConfig())
        queue.items[0].status = .completed
        queue.cancelItem(queue.items[0])
        XCTAssertEqual(queue.items[0].status, .completed)
    }

    // MARK: - Retry

    func testRetryResetsFailedItem() {
        let queue = DownloadQueue()
        queue.addURLs(["https://example.com/a"], config: makeConfig())
        let item = queue.items[0]
        item.status = .failed
        item.error = AppError(message: "test", recoverySuggestion: nil)
        item.downloadProgress = DownloadProgress(percentComplete: 50, summaryLine: "50%")
        queue.retryItem(item)
        XCTAssertEqual(item.status, .pending)
        XCTAssertNil(item.error)
        XCTAssertNil(item.downloadProgress)
        XCTAssertNil(item.title)
    }

    func testRetryPendingItemIsNoOp() {
        let queue = DownloadQueue()
        queue.addURLs(["https://example.com/a"], config: makeConfig())
        queue.retryItem(queue.items[0])
        XCTAssertEqual(queue.items[0].status, .pending)
    }

    // MARK: - Clear completed

    func testClearCompletedRemovesTerminalItems() {
        let queue = DownloadQueue()
        queue.addURLs(["https://a.com", "https://b.com", "https://c.com", "https://d.com"], config: makeConfig())
        queue.items[0].status = .completed
        queue.items[1].status = .failed
        queue.items[2].status = .cancelled
        queue.clearCompleted()
        XCTAssertEqual(queue.items.count, 1)
        XCTAssertEqual(queue.items[0].url, "https://d.com")
    }

    // MARK: - Config snapshot

    func testConfigSnapshotCapturesSettings() {
        let dir = URL(fileURLWithPath: "/tmp/test-output")
        let config = QueueItemConfig(
            outputDirectory: dir,
            cookiesFilePath: "/tmp/cookies.txt",
            extraOptions: [ParsedExtraOption(name: .retries, value: "5")],
            audioTranscodeFormat: .mp3,
            downloaderPreference: .aria2c,
            aria2cPath: "/opt/homebrew/bin/aria2c",
            qualityStrategy: .max1080p
        )
        let item = QueueItem(url: "https://example.com", config: config)
        XCTAssertEqual(item.config.outputDirectory, dir)
        XCTAssertEqual(item.config.cookiesFilePath, "/tmp/cookies.txt")
        XCTAssertEqual(item.config.extraOptions, [ParsedExtraOption(name: .retries, value: "5")])
        XCTAssertEqual(item.config.audioTranscodeFormat, .mp3)
        XCTAssertEqual(item.config.downloaderPreference, .aria2c)
        XCTAssertEqual(item.config.aria2cPath, "/opt/homebrew/bin/aria2c")
    }

    func testStartProcessingFallsBackWhenQueuedAria2cPathIsNoLongerExecutable() async throws {
        let queue = DownloadQueue()
        let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let resultFile = outputDirectory.appendingPathComponent("queued-result.mp4")
        let argsFile = outputDirectory.appendingPathComponent("argv.txt")
        let ytDlp = try makeDownloadScript(resultFile: resultFile, argsFile: argsFile)
        let ffmpeg = try makeExecutableStub()
        let staleAria2cPath = outputDirectory.appendingPathComponent("aria2c-stale").path

        queue.addURLs(
            ["https://example.com/watch?v=123"],
            config: makeConfig(
                outputDirectory: outputDirectory,
                downloaderPreference: .aria2c,
                aria2cPath: staleAria2cPath
            )
        )

        var logMessages: [String] = []
        queue.startProcessing(
            locator: BundledToolLocator(overrides: [.ytDlp: ytDlp, .ffmpeg: ffmpeg]),
            onLog: { _, _, message in
                logMessages.append(message)
            }
        )

        try await waitForTerminalStatus(of: queue.items[0])

        XCTAssertEqual(queue.items[0].status, .completed)
        let commandArguments = try String(contentsOf: argsFile, encoding: .utf8)
        XCTAssertFalse(commandArguments.contains("--downloader"))
        XCTAssertTrue(
            logMessages.contains { $0.contains("aria2c unavailable for queued item; falling back to built-in downloader") }
        )
    }

    // MARK: - Status

    func testStatusIsTerminal() {
        XCTAssertTrue(QueueItemStatus.completed.isTerminal)
        XCTAssertTrue(QueueItemStatus.failed.isTerminal)
        XCTAssertTrue(QueueItemStatus.cancelled.isTerminal)
        XCTAssertFalse(QueueItemStatus.pending.isTerminal)
        XCTAssertFalse(QueueItemStatus.active.isTerminal)
    }

    func testItemDefaultsToPending() {
        let item = QueueItem(url: "https://example.com", config: makeConfig())
        XCTAssertEqual(item.status, .pending)
        XCTAssertNil(item.downloadProgress)
        XCTAssertNil(item.outputURL)
        XCTAssertNil(item.error)
        XCTAssertNil(item.title)
    }

    private func waitForTerminalStatus(of item: QueueItem) async throws {
        for _ in 0 ..< 100 {
            if item.status.isTerminal {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Expected queue item to reach a terminal state")
        throw NSError(domain: "DownloadQueueTests", code: 1)
    }

    private func makeDownloadScript(resultFile: URL, argsFile: URL) throws -> URL {
        try makeExecutableScript(
            """
            #!/bin/sh
            printf '%s\n' "$@" > "\(argsFile.path)"
            touch "\(resultFile.path)"
            echo "\(resultFile.path)"
            """
        )
    }

    private func makeExecutableStub() throws -> URL {
        try makeExecutableScript(
            """
            #!/bin/sh
            exit 0
            """
        )
    }

    private func makeExecutableScript(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
