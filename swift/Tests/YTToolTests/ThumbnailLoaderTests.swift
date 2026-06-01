import XCTest
@testable import YTTool

final class ThumbnailLoaderTests: XCTestCase {
    func testNormalizedThumbnailRequestURLUpgradesHTTP() {
        let url = normalizedThumbnailRequestURL(from: "http://i0.hdslb.com/bfs/archive/cover.jpg")
        XCTAssertEqual(url?.absoluteString, "https://i0.hdslb.com/bfs/archive/cover.jpg")
    }

    func testNormalizedThumbnailRequestURLSupportsProtocolRelativeURL() {
        let url = normalizedThumbnailRequestURL(from: "//i0.hdslb.com/bfs/archive/cover.jpg")
        XCTAssertEqual(url?.absoluteString, "https://i0.hdslb.com/bfs/archive/cover.jpg")
    }

    func testBilibiliVideoIDParsesBVURL() {
        XCTAssertEqual(
            bilibiliVideoID(from: "https://www.bilibili.com/video/BV1xx411c7mD/?spm_id_from=333.337.search-card.all.click"),
            .bvid("BV1xx411c7mD")
        )
    }

    func testBilibiliVideoIDParsesAVURL() {
        XCTAssertEqual(
            bilibiliVideoID(from: "https://www.bilibili.com/video/av123456"),
            .aid("123456")
        )
    }

    func testBilibiliVideoIDRejectsNonBilibiliURL() {
        XCTAssertNil(bilibiliVideoID(from: "https://example.com/video/BV1xx411c7mD"))
    }
}
