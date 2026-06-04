import XCTest
@testable import YTTool

final class BilibiliFeedServiceTests: XCTestCase {
    // MARK: - Response parsing (seasons_series_list format)

    func testParsesTypicalSeasonsResponse() async throws {
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
        let videos = try await service.parseFeedResponse(data: data, channelID: "12345")

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

    func testParsesEmptySeasonsResponse() async throws {
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
        let videos = try await service.parseFeedResponse(data: Data(json.utf8), channelID: "12345")
        XCTAssertTrue(videos.isEmpty)
    }

    func testNonZeroCodeThrows() async {
        let json = """
        { "code": -400, "message": "请求错误" }
        """
        let service = BilibiliFeedService()
        do {
            _ = try await service.parseFeedResponse(data: Data(json.utf8), channelID: "12345")
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected
        }
    }

    func testProtocolRelativeThumbnailURLNormalized() async throws {
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
        let videos = try await service.parseFeedResponse(data: Data(json.utf8), channelID: "12345")
        XCTAssertEqual(videos[0].thumbnailURL, "https://i0.hdslb.com/bfs/archive/test.jpg")
    }

    func testHttpThumbnailUpgradedToHttps() async throws {
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
        let videos = try await service.parseFeedResponse(data: Data(json.utf8), channelID: "12345")
        XCTAssertEqual(videos[0].thumbnailURL, "https://i0.hdslb.com/bfs/archive/test.jpg")
    }

    func testMergesSeasonAndSeriesArchives() async throws {
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
        let videos = try await service.parseFeedResponse(data: Data(json.utf8), channelID: "12345")
        XCTAssertEqual(videos.count, 2)
        // Series video is newer, should be first
        XCTAssertEqual(videos[0].videoID, "BV1series")
        XCTAssertEqual(videos[1].videoID, "BV1season")
    }

    // MARK: - WBI signing

    func testGenerateMixinKey() {
        let imgKey = "7cd084941338484aae1ad9425b84077c"
        let subKey = "4932caff0ff746eab6f01bf08b70ac45"
        let mixinKey = BilibiliFeedService.generateMixinKey(imgKey: imgKey, subKey: subKey)
        XCTAssertEqual(mixinKey.count, 32)
        // Verify first few characters by manual mixin table application
        let raw = Array(imgKey + subKey)
        let expected0 = raw[46] // mixinTable[0] = 46
        XCTAssertEqual(mixinKey.first, expected0)
    }

    func testSignParamsProducesWRid() {
        let imgKey = "7cd084941338484aae1ad9425b84077c"
        let subKey = "4932caff0ff746eab6f01bf08b70ac45"
        let mixinKey = BilibiliFeedService.generateMixinKey(imgKey: imgKey, subKey: subKey)
        let params: [String: String] = [
            "mid": "24832017",
            "ps": "15",
            "tid": "0",
            "pn": "1",
            "order": "pubdate",
        ]
        let signed = BilibiliFeedService.signParams(params, mixinKey: mixinKey, timestamp: 1_717_415_280)
        XCTAssertNotNil(signed["w_rid"])
        XCTAssertEqual(signed["w_rid"]?.count, 32)
        XCTAssertEqual(signed["wts"], "1717415280")
        // All original params preserved
        XCTAssertEqual(signed["mid"], "24832017")
        XCTAssertEqual(signed["order"], "pubdate")
    }

    func testSignParamsDeterministic() {
        let mixinKey = "abcdefghijklmnopqrstuvwxyz012345"
        let params = ["mid": "123", "pn": "1"]
        let result1 = BilibiliFeedService.signParams(params, mixinKey: mixinKey, timestamp: 1000)
        let result2 = BilibiliFeedService.signParams(params, mixinKey: mixinKey, timestamp: 1000)
        XCTAssertEqual(result1["w_rid"], result2["w_rid"])
    }

    // MARK: - arc/search response parsing

    func testParsesArcSearchResponse() async throws {
        let json = """
        {
          "code": 0,
          "data": {
            "list": {
              "vlist": [
                {
                  "bvid": "BV1NE796rECh",
                  "title": "测试视频",
                  "created": 1717415280,
                  "pic": "//i2.hdslb.com/cover.jpg",
                  "author": "空山鸟语"
                },
                {
                  "bvid": "BV2test",
                  "title": "第二个视频",
                  "created": 1717400000,
                  "pic": "https://i2.hdslb.com/cover2.jpg",
                  "author": "空山鸟语"
                }
              ]
            },
            "page": { "pn": 1, "ps": 15, "count": 1151 }
          }
        }
        """
        let response = try JSONDecoder().decode(BilibiliArcSearchResponse.self, from: Data(json.utf8))
        let service = BilibiliFeedService()
        let videos = await service.parseArcSearchResponse(response)

        XCTAssertEqual(videos.count, 2)
        XCTAssertEqual(videos[0].videoID, "BV1NE796rECh")
        XCTAssertEqual(videos[0].title, "测试视频")
        XCTAssertEqual(videos[0].channelName, "空山鸟语")
        XCTAssertEqual(videos[0].thumbnailURL, "https://i2.hdslb.com/cover.jpg")
        XCTAssertEqual(videos[0].publishedDate, Date(timeIntervalSince1970: 1_717_415_280))
        XCTAssertEqual(videos[0].url, "https://www.bilibili.com/video/BV1NE796rECh")
    }

    func testParsesEmptyArcSearchResponse() async throws {
        let json = """
        {
          "code": 0,
          "data": {
            "list": { "vlist": [] },
            "page": { "pn": 1, "ps": 15, "count": 0 }
          }
        }
        """
        let response = try JSONDecoder().decode(BilibiliArcSearchResponse.self, from: Data(json.utf8))
        let service = BilibiliFeedService()
        let videos = await service.parseArcSearchResponse(response)
        XCTAssertTrue(videos.isEmpty)
    }

    func testArcSearchResponseNullVlist() async throws {
        let json = """
        {
          "code": 0,
          "data": { "list": {} }
        }
        """
        let response = try JSONDecoder().decode(BilibiliArcSearchResponse.self, from: Data(json.utf8))
        let service = BilibiliFeedService()
        let videos = await service.parseArcSearchResponse(response)
        XCTAssertTrue(videos.isEmpty)
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
}
