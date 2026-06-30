import XCTest
@testable import YTTool

@MainActor
final class DownloadHistoryStoreTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() async throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("YTToolTests-\(UUID().uuidString)")
            .appendingPathComponent("download_history.json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
    }

    func testCorruptedFileBacksUpAndLoadsEmpty() throws {
        try FileManager.default.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: tempURL)

        let store = DownloadHistoryStore(storageURL: tempURL)

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNotNil(store.recoveryMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path))
        let backups = try FileManager.default.contentsOfDirectory(atPath: tempURL.deletingLastPathComponent().path)
            .filter { $0.hasSuffix(".bak") }
        XCTAssertEqual(backups.count, 1)
    }

    func testClearStoredDataRemovesFileAndEntries() throws {
        let store = DownloadHistoryStore(storageURL: tempURL)
        let entry = DownloadHistoryEntry(
            id: UUID(),
            url: "https://example.com",
            title: "Video",
            outputPath: "/tmp/video.mp4",
            dateCompleted: Date(),
            succeeded: true,
            estimatedSizeBytes: nil
        )
        store.append(entry)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))

        try store.clearStoredData()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path))
    }
}
