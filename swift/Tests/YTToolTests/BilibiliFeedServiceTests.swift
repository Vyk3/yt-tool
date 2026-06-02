import XCTest
@testable import YTTool

final class BilibiliFeedServiceTests: XCTestCase {
    // MARK: - Response parsing (seasons_series_list format)

    func testParsesTypicalSeasonsResponse() throws {
        let json = """
        {
          "code": 0,
          "data": {
            "items_lists": {
              "page": { "page_num": 1, "page_size": 20, "total": 2 },
              "seasons_list": [
                {
                  "archives": [
                    {
                      "bvid": "BV1xx411c7mD",
                      "title": "测试视频标题",
                      "pic": "//i0.hdslb.com/bfs/archive/cover.jpg",
                      "ctime": 1700000000
                    },
                    {
                      "bvid": "BV1yy411c8nE",
                      "title": "第二个视频",
                      "pic": "https://i0.hdslb.com/bfs/archive/cover2.jpg",
                      "ctime": 1699900000
                    }
                  ]
                }
              ],
              "series_list": []
            }
          }
        }
        """
        let data = Data(json.utf8)
        let service = BilibiliFeedService()
        let videos = try awaitSync { try await service.parseFeedResponse(data: data, channelID: "12345") }

        XCTAssertEqual(videos.count, 2)

        // Sorted by ctime descending
        XCTAssertEqual(videos[0].videoID, "BV1xx411c7mD")
        XCTAssertEqual(videos[0].title, "测试视频标题")
        XCTAssertEqual(videos[0].url, "https://www.bilibili.com/video/BV1xx411c7mD")
        XCTAssertEqual(videos[0].thumbnailURL, "https://i0.hdslb.com/bfs/archive/cover.jpg")
        XCTAssertEqual(videos[0].publishedDate, Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertEqual(videos[1].videoID, "BV1yy411c8nE")
        XCTAssertEqual(videos[1].thumbnailURL, "https://i0.hdslb.com/bfs/archive/cover2.jpg")
    }

    func testParsesEmptySeasonsResponse() throws {
        let json = """
        {
          "code": 0,
          "data": {
            "items_lists": {
              "page": { "page_num": 1, "page_size": 20, "total": 0 },
              "seasons_list": [],
              "series_list": []
            }
          }
        }
        """
        let service = BilibiliFeedService()
        let videos = try awaitSync { try await service.parseFeedResponse(data: Data(json.utf8), channelID: "12345") }
        XCTAssertTrue(videos.isEmpty)
    }

    func testNonZeroCodeThrows() {
        let json = """
        { "code": -400, "message": "请求错误" }
        """
        let service = BilibiliFeedService()
        XCTAssertThrowsError(
            try awaitSync { try await service.parseFeedResponse(data: Data(json.utf8), channelID: "12345") }
        )
    }

    func testProtocolRelativeThumbnailURLNormalized() throws {
        let json = """
        {
          "code": 0,
          "data": {
            "items_lists": {
              "seasons_list": [{
                "archives": [{
                  "bvid": "BV1test",
                  "title": "Test",
                  "pic": "//i0.hdslb.com/bfs/archive/test.jpg",
                  "ctime": 1700000000
                }]
              }],
              "series_list": []
            }
          }
        }
        """
        let service = BilibiliFeedService()
        let videos = try awaitSync { try await service.parseFeedResponse(data: Data(json.utf8), channelID: "12345") }
        XCTAssertEqual(videos[0].thumbnailURL, "https://i0.hdslb.com/bfs/archive/test.jpg")
    }

    func testHttpThumbnailUpgradedToHttps() throws {
        let json = """
        {
          "code": 0,
          "data": {
            "items_lists": {
              "seasons_list": [{
                "archives": [{
                  "bvid": "BV1test",
                  "title": "Test",
                  "pic": "http://i0.hdslb.com/bfs/archive/test.jpg",
                  "ctime": 1700000000
                }]
              }],
              "series_list": []
            }
          }
        }
        """
        let service = BilibiliFeedService()
        let videos = try awaitSync { try await service.parseFeedResponse(data: Data(json.utf8), channelID: "12345") }
        XCTAssertEqual(videos[0].thumbnailURL, "https://i0.hdslb.com/bfs/archive/test.jpg")
    }

    func testMergesSeasonAndSeriesArchives() throws {
        let json = """
        {
          "code": 0,
          "data": {
            "items_lists": {
              "seasons_list": [{
                "archives": [{
                  "bvid": "BV1season",
                  "title": "From Season",
                  "pic": "https://example.com/s.jpg",
                  "ctime": 1700000000
                }]
              }],
              "series_list": [{
                "archives": [{
                  "bvid": "BV1series",
                  "title": "From Series",
                  "pic": "https://example.com/r.jpg",
                  "ctime": 1700100000
                }]
              }]
            }
          }
        }
        """
        let service = BilibiliFeedService()
        let videos = try awaitSync { try await service.parseFeedResponse(data: Data(json.utf8), channelID: "12345") }
        XCTAssertEqual(videos.count, 2)
        // Series video is newer, should be first
        XCTAssertEqual(videos[0].videoID, "BV1series")
        XCTAssertEqual(videos[1].videoID, "BV1season")
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
