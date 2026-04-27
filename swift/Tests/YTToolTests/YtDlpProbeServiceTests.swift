import XCTest
@testable import YTTool

final class YtDlpProbeServiceTests: XCTestCase {
    func testProbeTreatsNullStdoutAsFailure() async throws {
        let scriptURL = try makeExecutableScript(
            """
            #!/bin/sh
            echo "ERROR: network unavailable" >&2
            echo "null"
            exit 0
            """
        )

        let service = YtDlpProbeService(
            locator: BundledToolLocator(overrides: [.ytDlp: scriptURL]),
            runner: ProcessRunner()
        )

        do {
            _ = try await service.probe(url: "https://example.com/video")
            XCTFail("Expected probe to fail")
        } catch let error as AppError {
            XCTAssertEqual(error.message, "yt-dlp probe failed.")
            XCTAssertEqual(error.recoverySuggestion, "ERROR: network unavailable")
        }
    }

    func testProbeParsesSuccessfulJSONOutput() async throws {
        let scriptURL = try makeExecutableScript(
            """
            #!/bin/sh
            cat <<'EOF'
            {"title":"fixture","webpage_url":"https://example.com/video","formats":[{"format_id":"137","vcodec":"avc1","acodec":"none","height":1080,"fps":30,"tbr":4500},{"format_id":"251","vcodec":"none","acodec":"opus","abr":160,"ext":"webm"}]}
            EOF
            """
        )

        let service = YtDlpProbeService(
            locator: BundledToolLocator(overrides: [.ytDlp: scriptURL]),
            runner: ProcessRunner()
        )

        let info = try await service.probe(url: "https://example.com/video")
        XCTAssertEqual(info.title, "fixture")
        XCTAssertEqual(info.videoFormats.map(\.id), ["137"])
        XCTAssertEqual(info.audioFormats.map(\.id), ["251"])
    }

    private func makeExecutableScript(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .notDirectory)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
