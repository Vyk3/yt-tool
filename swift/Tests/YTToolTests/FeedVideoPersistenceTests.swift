import XCTest
@testable import YTTool

/// Verifies FeedVideo Codable round-trip and UserDefaults persistence —
/// the same mechanism SubscriptionPollingManager uses to keep new-video
/// state across app restarts.
final class FeedVideoPersistenceTests: XCTestCase {
    private let testKey = "test_subscriptionNewVideos_\(UUID().uuidString)"

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    // MARK: - Codable round-trip

    func testSingleVideoCodableRoundTrip() throws {
        let video = FeedVideo(
            videoID: "abc123",
            title: "Test Video",
            channelName: "Test Channel",
            publishedDate: Date(timeIntervalSince1970: 1_700_000_000),
            url: "https://www.youtube.com/watch?v=abc123"
        )

        let data = try JSONEncoder().encode([video])
        let decoded = try JSONDecoder().decode([FeedVideo].self, from: data)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].videoID, "abc123")
        XCTAssertEqual(decoded[0].title, "Test Video")
        XCTAssertEqual(decoded[0].channelName, "Test Channel")
        XCTAssertEqual(decoded[0].url, "https://www.youtube.com/watch?v=abc123")
        XCTAssertEqual(decoded[0].publishedDate, video.publishedDate)
    }

    func testMultipleVideosWithOptionalDate() throws {
        let videos = [
            FeedVideo(
                videoID: "vid1",
                title: "First",
                channelName: "Ch A",
                publishedDate: Date(timeIntervalSince1970: 1_700_000_000),
                url: "https://www.youtube.com/watch?v=vid1"
            ),
            FeedVideo(
                videoID: "vid2",
                title: "Second",
                channelName: "Ch B",
                publishedDate: nil,
                url: "https://www.youtube.com/watch?v=vid2"
            ),
        ]

        let data = try JSONEncoder().encode(videos)
        let decoded = try JSONDecoder().decode([FeedVideo].self, from: data)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].videoID, "vid1")
        XCTAssertNotNil(decoded[0].publishedDate)
        XCTAssertEqual(decoded[1].videoID, "vid2")
        XCTAssertNil(decoded[1].publishedDate)
    }

    func testEmptyArrayCodableRoundTrip() throws {
        let videos: [FeedVideo] = []
        let data = try JSONEncoder().encode(videos)
        let decoded = try JSONDecoder().decode([FeedVideo].self, from: data)
        XCTAssertTrue(decoded.isEmpty)
    }

    // MARK: - UserDefaults persistence (mirrors SubscriptionPollingManager)

    func testWriteAndReadFromUserDefaults() throws {
        let videos = [
            FeedVideo(
                videoID: "persist1",
                title: "Persisted Video",
                channelName: "Persisted Channel",
                publishedDate: Date(),
                url: "https://www.youtube.com/watch?v=persist1"
            ),
        ]

        // Write — same path as saveNewVideos()
        let encoded = try JSONEncoder().encode(videos)
        UserDefaults.standard.set(encoded, forKey: testKey)

        // Read back — same path as loadNewVideos()
        guard let loaded = UserDefaults.standard.data(forKey: testKey) else {
            XCTFail("No data found in UserDefaults for key \(testKey)")
            return
        }
        let decoded = try JSONDecoder().decode([FeedVideo].self, from: loaded)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].videoID, "persist1")
        XCTAssertEqual(decoded[0].title, "Persisted Video")
    }

    func testMissingKeyReturnsNilData() {
        let data = UserDefaults.standard.data(
            forKey: "nonexistent_key_\(UUID().uuidString)"
        )
        XCTAssertNil(data)
    }

    func testCorruptedDataDecodesAsNil() {
        UserDefaults.standard.set(Data("not json".utf8), forKey: testKey)

        guard let data = UserDefaults.standard.data(forKey: testKey) else {
            XCTFail("Data should exist in UserDefaults")
            return
        }
        let decoded = try? JSONDecoder().decode([FeedVideo].self, from: data)
        // loadNewVideos() uses `?? []` — corrupt data gracefully becomes empty
        XCTAssertNil(decoded)
    }

    // MARK: - Dismiss / clear simulation

    func testDismissRemovesOneAndPersists() throws {
        var videos = [
            FeedVideo(videoID: "a", title: "A", channelName: "C", publishedDate: nil, url: "u1"),
            FeedVideo(videoID: "b", title: "B", channelName: "C", publishedDate: nil, url: "u2"),
            FeedVideo(videoID: "c", title: "C", channelName: "C", publishedDate: nil, url: "u3"),
        ]

        // Simulate dismissVideo("b")
        videos.removeAll { $0.videoID == "b" }
        let data = try JSONEncoder().encode(videos)
        UserDefaults.standard.set(data, forKey: testKey)

        // Re-load
        let loaded = try XCTUnwrap(UserDefaults.standard.data(forKey: testKey))
        let decoded = try JSONDecoder().decode([FeedVideo].self, from: loaded)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded.map(\.videoID), ["a", "c"])
    }

    func testClearAllPersistsEmpty() throws {
        // Write some videos first
        let videos = [
            FeedVideo(videoID: "x", title: "X", channelName: "C", publishedDate: nil, url: "u"),
        ]
        let data = try JSONEncoder().encode(videos)
        UserDefaults.standard.set(data, forKey: testKey)

        // Simulate clearAllNewVideos()
        let empty: [FeedVideo] = []
        let emptyData = try JSONEncoder().encode(empty)
        UserDefaults.standard.set(emptyData, forKey: testKey)

        // Re-load
        let loaded = try XCTUnwrap(UserDefaults.standard.data(forKey: testKey))
        let decoded = try JSONDecoder().decode([FeedVideo].self, from: loaded)
        XCTAssertTrue(decoded.isEmpty)
    }
}
