import XCTest
@testable import YTTool

final class YtDlpArgumentsTests: XCTestCase {

    // MARK: - isYouTubeURL

    func testYouTubeDotComIsRecognised() {
        XCTAssertTrue(isYouTubeURL("https://www.youtube.com/watch?v=abc"))
        XCTAssertTrue(isYouTubeURL("https://youtube.com/watch?v=abc"))
        XCTAssertTrue(isYouTubeURL("https://m.youtube.com/watch?v=abc"))
        XCTAssertTrue(isYouTubeURL("https://youtu.be/abc"))
    }

    func testNonYouTubeURLIsNotRecognised() {
        XCTAssertFalse(isYouTubeURL("https://vimeo.com/123"))
        XCTAssertFalse(isYouTubeURL("https://example.com/video"))
        XCTAssertFalse(isYouTubeURL("https://notyoutube.com/watch?v=abc"))
        XCTAssertFalse(isYouTubeURL("not-a-url"))
    }

    // MARK: - buildProbeArguments — P1 baseline regression

    func testProbeArgumentsNonYouTubeMatchesP1Baseline() {
        let url = "https://vimeo.com/123"
        let args = buildProbeArguments(url: url)
        XCTAssertEqual(args, ["--dump-single-json", "--no-playlist", url])
    }

    func testProbeArgumentsYouTubeUsesDefaultPlayerClient() {
        let url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        let args = buildProbeArguments(url: url)
        XCTAssert(args.contains("--dump-single-json"))
        XCTAssert(args.contains("--no-playlist"))
        XCTAssert(args.contains("--extractor-args"))
        XCTAssert(args.contains("youtube:player_client=default"))
        XCTAssertEqual(args.last, url)
    }

    // MARK: - buildDownloadArguments — P1 baseline regression

    func testDownloadArgumentsNonYouTubeMatchesP1Baseline() {
        let url = "https://vimeo.com/123"
        let args = buildDownloadArguments(
            url: url,
            formatSelector: "137+251",
            outputTemplate: "/tmp/%(title)s.%(ext)s",
            ffmpegDirectory: "/usr/local/bin"
        )
        XCTAssertEqual(args, [
            "-f", "137+251",
            "-o", "/tmp/%(title)s.%(ext)s",
            "--ffmpeg-location", "/usr/local/bin",
            "--print", "after_move:filepath",
            "--progress",
            "--newline",
            "--no-playlist",
            url,
        ])
    }

    func testDownloadArgumentsYouTubeUsesDefaultPlayerClient() {
        let url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        let args = buildDownloadArguments(
            url: url,
            formatSelector: "bestvideo+bestaudio/best",
            outputTemplate: "/tmp/%(title)s.%(ext)s",
            ffmpegDirectory: "/usr/local/bin"
        )
        XCTAssert(args.contains("-f"))
        XCTAssert(args.contains("--no-playlist"))
        XCTAssert(args.contains("--extractor-args"))
        XCTAssert(args.contains("youtube:player_client=default"))
        XCTAssert(args.contains("--concurrent-fragments"))
        XCTAssert(args.contains("4"))
        XCTAssert(args.contains("--embed-thumbnail"))
        XCTAssert(args.contains("--embed-chapters"))
        XCTAssert(args.contains("--embed-metadata"))
        XCTAssertEqual(args.last, url)
    }
}
