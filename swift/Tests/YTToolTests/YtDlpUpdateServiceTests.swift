import XCTest
@testable import YTTool

final class YtDlpUpdateServiceTests: XCTestCase {
    // MARK: - GitHub API parsing

    func testParseStableRelease() throws {
        let json = """
        {
            "tag_name": "2025.03.31",
            "assets": [
                {
                    "name": "yt-dlp",
                    "browser_download_url": "https://example.com/yt-dlp",
                    "digest": "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
                },
                {
                    "name": "yt-dlp_macos",
                    "browser_download_url": "https://example.com/yt-dlp_macos",
                    "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                },
                {
                    "name": "yt-dlp_macos.zip",
                    "browser_download_url": "https://example.com/yt-dlp_macos.zip",
                    "digest": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
                }
            ]
        }
        """.data(using: .utf8)!

        let info = try YtDlpUpdateService.parseRelease(from: json)
        XCTAssertEqual(info.version, "2025.03.31")
        XCTAssertEqual(info.downloadURL.absoluteString, "https://example.com/yt-dlp")
        XCTAssertEqual(info.sha256, "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
    }

    func testParseNightlyRelease() throws {
        let json = """
        {
            "tag_name": "2025.03.31.123456",
            "assets": [
                {
                    "name": "yt-dlp",
                    "browser_download_url": "https://example.com/nightly/yt-dlp",
                    "digest": "sha256:abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd"
                }
            ]
        }
        """.data(using: .utf8)!

        let info = try YtDlpUpdateService.parseRelease(from: json)
        XCTAssertEqual(info.version, "2025.03.31.123456")
        XCTAssertEqual(info.sha256, "abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd")
    }

    func testParseMissingMacOSAssetThrows() {
        let json = """
        {
            "tag_name": "2025.03.31",
            "assets": [
                {
                    "name": "yt-dlp_linux",
                    "browser_download_url": "https://example.com/yt-dlp_linux",
                    "digest": "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
                }
            ]
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try YtDlpUpdateService.parseRelease(from: json)) { error in
            let appError = error as? AppError
            XCTAssertNotNil(appError)
            XCTAssertTrue(appError?.recoverySuggestion?.contains("No yt-dlp zipapp") ?? false)
        }
    }

    func testParseMissingDigestThrows() {
        let json = """
        {
            "tag_name": "2025.03.31",
            "assets": [
                {"name": "yt-dlp", "browser_download_url": "https://example.com/yt-dlp"}
            ]
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try YtDlpUpdateService.parseRelease(from: json)) { error in
            let appError = error as? AppError
            XCTAssertNotNil(appError)
            XCTAssertTrue(appError?.recoverySuggestion?.contains("digest unavailable") ?? false)
        }
    }

    func testParseUnsupportedDigestThrows() {
        let json = """
        {
            "tag_name": "2025.03.31",
            "assets": [
                {
                    "name": "yt-dlp",
                    "browser_download_url": "https://example.com/yt-dlp",
                    "digest": "sha512:0123"
                }
            ]
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try YtDlpUpdateService.parseRelease(from: json)) { error in
            let appError = error as? AppError
            XCTAssertNotNil(appError)
            XCTAssertTrue(appError?.recoverySuggestion?.contains("Unsupported") ?? false)
        }
    }

    func testParseInvalidSHA256DigestThrows() {
        let json = """
        {
            "tag_name": "2025.03.31",
            "assets": [
                {
                    "name": "yt-dlp",
                    "browser_download_url": "https://example.com/yt-dlp",
                    "digest": "sha256:not-a-valid-digest"
                }
            ]
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try YtDlpUpdateService.parseRelease(from: json)) { error in
            let appError = error as? AppError
            XCTAssertNotNil(appError)
            XCTAssertTrue(appError?.recoverySuggestion?.contains("Invalid") ?? false)
        }
    }

    func testVerifySHA256MatchesFileContents() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try Data("hello".utf8).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        try YtDlpUpdateService.verifySHA256(
            of: tempFile,
            expected: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
    }

    func testVerifySHA256RejectsMismatch() throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try Data("hello".utf8).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        XCTAssertThrowsError(try YtDlpUpdateService.verifySHA256(
            of: tempFile,
            expected: "0000000000000000000000000000000000000000000000000000000000000000"
        )) { error in
            let appError = error as? AppError
            XCTAssertNotNil(appError)
            XCTAssertTrue(appError?.recoverySuggestion?.contains("SHA256 mismatch") ?? false)
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

    func testUserLocalZipappURLConstruction() {
        let url = YtDlpUpdateService.userLocalZipappURL
        XCTAssertTrue(url.path.hasSuffix("/YTTool/Binaries/yt-dlp-zipapp"))
    }

    // MARK: - Shell escaping

    func testShellEscapeSimplePath() {
        let result = YtDlpUpdateService.shellEscapeSingleQuoted("/Applications/YTTool.app/Contents/Resources/Python/bin/python3.12")
        XCTAssertEqual(result, "'/Applications/YTTool.app/Contents/Resources/Python/bin/python3.12'")
    }

    func testShellEscapePathWithSpaces() {
        let result = YtDlpUpdateService.shellEscapeSingleQuoted("/Users/test user/Apps/YTTool.app/Contents/Resources/Python/bin/python3.12")
        XCTAssertEqual(result, "'/Users/test user/Apps/YTTool.app/Contents/Resources/Python/bin/python3.12'")
    }

    func testShellEscapePathWithSingleQuote() {
        let result = YtDlpUpdateService.shellEscapeSingleQuoted("/Users/it's me/Apps/python3.12")
        XCTAssertEqual(result, "'/Users/it'\\''s me/Apps/python3.12'")
    }

    func testShellEscapePathWithDollarSign() {
        let result = YtDlpUpdateService.shellEscapeSingleQuoted("/Users/$HOME/Apps/python3.12")
        XCTAssertEqual(result, "'/Users/$HOME/Apps/python3.12'")
    }

    func testShellEscapePathWithBackticks() {
        let result = YtDlpUpdateService.shellEscapeSingleQuoted("/Users/`whoami`/Apps/python3.12")
        XCTAssertEqual(result, "'/Users/`whoami`/Apps/python3.12'")
    }

    func testShellEscapeEmptyPath() {
        let result = YtDlpUpdateService.shellEscapeSingleQuoted("")
        XCTAssertEqual(result, "''")
    }

    func testLocateSkipsNonExecutableUserLocal() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let nonExecFile = tempDir.appendingPathComponent("yt-dlp")
        FileManager.default.createFile(atPath: nonExecFile.path, contents: nil)

        let locator = BundledToolLocator(overrides: [.ytDlp: nonExecFile])
        XCTAssertThrowsError(try locator.locate(.ytDlp))
    }

    // MARK: - Version comparison (isVersionNewer)

    func testIsVersionNewerStable() {
        XCTAssertTrue(AppState.isVersionNewer("2025.04.01", than: "2025.03.31"))
        XCTAssertFalse(AppState.isVersionNewer("2025.03.31", than: "2025.03.31"))
        XCTAssertFalse(AppState.isVersionNewer("2025.03.30", than: "2025.03.31"))
    }

    func testIsVersionNewerNightly() {
        XCTAssertTrue(AppState.isVersionNewer("2025.03.31.123457", than: "2025.03.31.123456"))
        XCTAssertFalse(AppState.isVersionNewer("2025.03.31.123456", than: "2025.03.31.123456"))
    }

    func testIsVersionNewerCrossChannel() {
        XCTAssertTrue(AppState.isVersionNewer("2025.04.01.000001", than: "2025.03.31"))
    }
}
