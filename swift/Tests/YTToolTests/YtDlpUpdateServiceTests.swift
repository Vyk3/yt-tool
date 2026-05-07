import XCTest
@testable import YTTool

final class YtDlpUpdateServiceTests: XCTestCase {
    // MARK: - GitHub API parsing

    func testParseStableRelease() throws {
        let json = """
        {
            "tag_name": "2025.03.31",
            "assets": [
                {"name": "yt-dlp", "browser_download_url": "https://example.com/yt-dlp"},
                {"name": "yt-dlp_macos", "browser_download_url": "https://example.com/yt-dlp_macos"},
                {"name": "yt-dlp_macos.zip", "browser_download_url": "https://example.com/yt-dlp_macos.zip"}
            ]
        }
        """.data(using: .utf8)!

        let info = try YtDlpUpdateService.parseRelease(from: json)
        XCTAssertEqual(info.version, "2025.03.31")
        XCTAssertEqual(info.downloadURL.absoluteString, "https://example.com/yt-dlp_macos")
    }

    func testParseNightlyRelease() throws {
        let json = """
        {
            "tag_name": "2025.03.31.123456",
            "assets": [
                {"name": "yt-dlp_macos", "browser_download_url": "https://example.com/nightly/yt-dlp_macos"}
            ]
        }
        """.data(using: .utf8)!

        let info = try YtDlpUpdateService.parseRelease(from: json)
        XCTAssertEqual(info.version, "2025.03.31.123456")
    }

    func testParseMissingMacOSAssetThrows() {
        let json = """
        {
            "tag_name": "2025.03.31",
            "assets": [
                {"name": "yt-dlp_linux", "browser_download_url": "https://example.com/yt-dlp_linux"}
            ]
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try YtDlpUpdateService.parseRelease(from: json)) { error in
            let appError = error as? AppError
            XCTAssertNotNil(appError)
            XCTAssertTrue(appError?.recoverySuggestion?.contains("No macOS binary") ?? false)
        }
    }

    func testParseEmptyAssetsThrows() {
        let json = """
        {
            "tag_name": "2025.03.31",
            "assets": []
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try YtDlpUpdateService.parseRelease(from: json))
    }

    func testParseInvalidJSONThrows() {
        let json = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try YtDlpUpdateService.parseRelease(from: json))
    }

    // MARK: - Version comparison

    func testStableVersionComparisonNewer() {
        XCTAssertTrue("2025.04.01" > "2025.03.31")
    }

    func testStableVersionComparisonSame() {
        XCTAssertFalse("2025.03.31" > "2025.03.31")
    }

    func testStableVersionComparisonOlder() {
        XCTAssertFalse("2025.03.30" > "2025.03.31")
    }

    func testNightlyVersionComparison() {
        XCTAssertTrue("2025.03.31.123457" > "2025.03.31.123456")
        XCTAssertTrue("2025.04.01.000001" > "2025.03.31.999999")
    }

    // MARK: - UpdateChannel

    func testUpdateChannelAPIURLs() {
        XCTAssertTrue(UpdateChannel.stable.apiURL.absoluteString.contains("yt-dlp/yt-dlp/"))
        XCTAssertTrue(UpdateChannel.nightly.apiURL.absoluteString.contains("yt-dlp-nightly-builds"))
    }

    func testUpdateChannelLabels() {
        XCTAssertEqual(UpdateChannel.stable.label, "Stable")
        XCTAssertEqual(UpdateChannel.nightly.label, "Nightly")
    }

    // MARK: - UpdateState

    func testUpdateStateEquality() {
        XCTAssertEqual(UpdateState.idle, UpdateState.idle)
        XCTAssertEqual(UpdateState.checking, UpdateState.checking)
        XCTAssertEqual(
            UpdateState.available(current: "a", latest: "b"),
            UpdateState.available(current: "a", latest: "b")
        )
        XCTAssertNotEqual(UpdateState.idle, UpdateState.checking)
    }

    // MARK: - BundledToolLocator user-local priority

    func testCandidateURLsIncludesUserLocalForYtDlp() {
        let locator = BundledToolLocator()
        let candidates = locator.candidateURLs(for: .ytDlp)
        XCTAssertTrue(candidates.count >= 2)
        let firstPath = candidates[0].path
        XCTAssertTrue(firstPath.contains("Application Support/YTTool/Binaries/yt-dlp"))
    }

    func testCandidateURLsExcludesUserLocalForFFmpeg() {
        let locator = BundledToolLocator()
        let candidates = locator.candidateURLs(for: .ffmpeg)
        for candidate in candidates {
            XCTAssertFalse(candidate.path.contains("Application Support/YTTool/Binaries"))
        }
    }

    func testUserLocalURLConstruction() {
        let url = BundledToolLocator.userLocalURL(for: .ytDlp)
        XCTAssertTrue(url.path.hasSuffix("/YTTool/Binaries/yt-dlp"))
    }
}
