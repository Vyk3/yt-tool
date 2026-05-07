import XCTest
@testable import YTTool

@MainActor
final class DownloadQueueTests: XCTestCase {
    private func makeConfig(
        outputDirectory: URL = URL(fileURLWithPath: "/tmp"),
        audioTranscodeFormat: AudioTranscodeFormat = .original,
        downloaderPreference: DownloaderPreference = .native
    ) -> QueueItemConfig {
        QueueItemConfig(
            outputDirectory: outputDirectory,
            cookiesFilePath: nil,
            extraArguments: [],
            audioTranscodeFormat: audioTranscodeFormat,
            downloaderPreference: downloaderPreference
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

    // MARK: - Move

    func testMoveItem() {
        let queue = DownloadQueue()
        queue.addURLs(["https://a.com", "https://b.com", "https://c.com"], config: makeConfig())
        queue.moveItem(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(queue.items[0].url, "https://c.com")
        XCTAssertEqual(queue.items[1].url, "https://a.com")
        XCTAssertEqual(queue.items[2].url, "https://b.com")
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
            extraArguments: ["--playlist-items", "1"],
            audioTranscodeFormat: .mp3,
            downloaderPreference: .aria2c
        )
        let item = QueueItem(url: "https://example.com", config: config)
        XCTAssertEqual(item.config.outputDirectory, dir)
        XCTAssertEqual(item.config.cookiesFilePath, "/tmp/cookies.txt")
        XCTAssertEqual(item.config.extraArguments, ["--playlist-items", "1"])
        XCTAssertEqual(item.config.audioTranscodeFormat, .mp3)
        XCTAssertEqual(item.config.downloaderPreference, .aria2c)
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
}
