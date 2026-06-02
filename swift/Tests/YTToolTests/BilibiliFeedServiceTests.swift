import XCTest
@testable import YTTool

final class BilibiliFeedServiceTests: XCTestCase {
    // MARK: - Response parsing

    func testParsesTypicalArcSearchResponse() throws {
        let json = """
        {
          "code": 0,
          "data": {
            "list": {
              "vlist": [
                {
                  "bvid": "BV1xx411c7mD",
                  "title": "测试视频标题",
                  "pic": "//i0.hdslb.com/bfs/archive/cover.jpg",
                  "created": 1700000000,
                  "author": "测试UP主"
                },
                {
                  "bvid": "BV1yy411c8nE",
                  "title": "第二个视频",
                  "pic": "https://i0.hdslb.com/bfs/archive/cover2.jpg",
                  "created": 1699900000,
                  "author": "测试UP主"
                }
              ]
            }
          }
        }
        """
        let data = Data(json.utf8)
        let service = BilibiliFeedService()
        let videos = try awaitSync { try await service.parseFeedResponse(data: data) }

        XCTAssertEqual(videos.count, 2)

        XCTAssertEqual(videos[0].videoID, "BV1xx411c7mD")
        XCTAssertEqual(videos[0].title, "测试视频标题")
        XCTAssertEqual(videos[0].channelName, "测试UP主")
        XCTAssertEqual(videos[0].url, "https://www.bilibili.com/video/BV1xx411c7mD")
        XCTAssertEqual(videos[0].thumbnailURL, "https://i0.hdslb.com/bfs/archive/cover.jpg")
        XCTAssertEqual(videos[0].publishedDate, Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertEqual(videos[1].videoID, "BV1yy411c8nE")
        XCTAssertEqual(videos[1].thumbnailURL, "https://i0.hdslb.com/bfs/archive/cover2.jpg")
    }

    func testParsesEmptyVlist() throws {
        let json = """
        { "code": 0, "data": { "list": { "vlist": [] } } }
        """
        let service = BilibiliFeedService()
        let videos = try awaitSync { try await service.parseFeedResponse(data: Data(json.utf8)) }
        XCTAssertTrue(videos.isEmpty)
    }

    func testNonZeroCodeThrows() {
        let json = """
        { "code": -403, "message": "访问权限不足" }
        """
        let service = BilibiliFeedService()
        XCTAssertThrowsError(
            try awaitSync { try await service.parseFeedResponse(data: Data(json.utf8)) }
        )
    }

    func testNullDataFieldThrows() {
        let json = """
        { "code": -352, "data": null }
        """
        let service = BilibiliFeedService()
        XCTAssertThrowsError(
            try awaitSync { try await service.parseFeedResponse(data: Data(json.utf8)) }
        )
    }

    func testProtocolRelativeThumbnailURLNormalized() throws {
        let json = """
        {
          "code": 0,
          "data": {
            "list": {
              "vlist": [{
                "bvid": "BV1test",
                "title": "Test",
                "pic": "//i0.hdslb.com/bfs/archive/test.jpg",
                "created": 1700000000,
                "author": "Author"
              }]
            }
          }
        }
        """
        let service = BilibiliFeedService()
        let videos = try awaitSync { try await service.parseFeedResponse(data: Data(json.utf8)) }
        XCTAssertEqual(videos[0].thumbnailURL, "https://i0.hdslb.com/bfs/archive/test.jpg")
    }

    // MARK: - Platform detection

    func testIsBilibiliURL() {
        XCTAssertTrue(isBilibiliURL("https://space.bilibili.com/12345"))
        XCTAssertTrue(isBilibiliURL("https://space.bilibili.com/12345/video"))
        XCTAssertTrue(isBilibiliURL("https://www.bilibili.com/video/BV1xx411c7mD"))
        XCTAssertTrue(isBilibiliURL("https://bilibili.com/video/BV1xx411c7mD"))
        XCTAssertFalse(isBilibiliURL("https://www.youtube.com/watch?v=abc"))
        XCTAssertFalse(isBilibiliURL("https://example.com"))
        XCTAssertFalse(isBilibiliURL("not a url"))
    }

    func testIsYouTubeSubscriptionURL() {
        XCTAssertTrue(isYouTubeSubscriptionURL("https://www.youtube.com/channel/UC123"))
        XCTAssertTrue(isYouTubeSubscriptionURL("https://youtube.com/@handle"))
        XCTAssertTrue(isYouTubeSubscriptionURL("https://youtu.be/abc123"))
        XCTAssertFalse(isYouTubeSubscriptionURL("https://bilibili.com/video/BV1xx"))
        XCTAssertFalse(isYouTubeSubscriptionURL("not a url"))
    }

    func testPlatformDetect() {
        XCTAssertEqual(Platform.detect(from: "https://www.youtube.com/channel/UC123"), .youtube)
        XCTAssertEqual(Platform.detect(from: "https://youtu.be/abc"), .youtube)
        XCTAssertEqual(Platform.detect(from: "https://space.bilibili.com/12345"), .bilibili)
        XCTAssertEqual(Platform.detect(from: "https://www.bilibili.com/video/BV1xx"), .bilibili)
        XCTAssertNil(Platform.detect(from: "https://example.com"))
        XCTAssertNil(Platform.detect(from: "not a url"))
    }

    // MARK: - Platform Codable

    func testPlatformCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for platform in [Platform.youtube, Platform.bilibili] {
            let data = try encoder.encode(platform)
            let decoded = try decoder.decode(Platform.self, from: data)
            XCTAssertEqual(decoded, platform)
        }
    }

    func testBilibiliSubscriptionCodableRoundTrip() throws {
        let sub = ChannelSubscription(
            id: UUID(),
            channelID: "12345",
            channelName: "测试UP主",
            channelURL: "https://space.bilibili.com/12345",
            dateAdded: Date(timeIntervalSince1970: 1_700_000_000),
            isEnabled: true,
            platform: .bilibili
        )
        let data = try JSONEncoder().encode(sub)
        let decoded = try JSONDecoder().decode(ChannelSubscription.self, from: data)
        XCTAssertEqual(decoded.platform, .bilibili)
        XCTAssertEqual(decoded.channelID, "12345")
        XCTAssertEqual(decoded.channelName, "测试UP主")
        XCTAssertEqual(decoded.channelURL, "https://space.bilibili.com/12345")
    }

    // MARK: - Helpers

    private func awaitSync<T>(_ block: @escaping @Sendable () async throws -> T) throws -> T {
        let expectation = expectation(description: "async")
        nonisolated(unsafe) var result: Result<T, Error>!
        Task {
            do {
                result = .success(try await block())
            } catch {
                result = .failure(error)
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        return try result.get()
    }
}
