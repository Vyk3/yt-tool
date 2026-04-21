import XCTest
@testable import YTTool

final class ProbeParserTests: XCTestCase {
    func testParseNormalProbePayload() throws {
        let info = try ProbeParser().parse(Self.normalProbeJSON.data(using: .utf8)!)

        XCTAssertEqual(info.title, "Example Video")
        XCTAssertEqual(info.duration, 95)
        XCTAssertEqual(info.webpageURL, "https://example.com/watch?v=123")
        XCTAssertEqual(info.videoFormats.map(\.id), ["137"])
        XCTAssertEqual(info.audioFormats.map(\.id), ["251"])
        XCTAssertEqual(info.videoFormats.first?.note, "no audio")
    }

    func testParseToleratesMissingOptionalFields() throws {
        let info = try ProbeParser().parse(Self.missingFieldsJSON.data(using: .utf8)!)

        XCTAssertEqual(info.title, "unknown")
        XCTAssertEqual(info.videoFormats.first?.resolution, "tiny")
        XCTAssertEqual(info.videoFormats.first?.fps, 0)
        XCTAssertEqual(info.audioFormats.first?.note, "")
    }

    func testParseInvalidJSONThrowsAppError() {
        XCTAssertThrowsError(try ProbeParser().parse(Data("{bad json".utf8))) { error in
            guard let appError = error as? AppError else {
                return XCTFail("Expected AppError, got \(error)")
            }
            XCTAssertEqual(appError.message, "Failed to decode probe output.")
        }
    }

    private static let normalProbeJSON = """
    {
      "title": "Example Video",
      "duration": 95,
      "webpage_url": "https://example.com/watch?v=123",
      "formats": [
        {
          "format_id": "137",
          "vcodec": "avc1.640028",
          "acodec": "none",
          "height": 1080,
          "fps": 30,
          "tbr": 4500,
          "filesize": 125000000
        },
        {
          "format_id": "251",
          "vcodec": "none",
          "acodec": "opus",
          "abr": 160,
          "ext": "webm",
          "format_note": "medium",
          "filesize_approx": 8000000
        }
      ]
    }
    """

    private static let missingFieldsJSON = """
    {
      "title": "\\n\\t",
      "formats": [
        {
          "format_id": "18",
          "vcodec": "avc1",
          "acodec": "mp4a.40.2",
          "format_note": "tiny"
        },
        {
          "format_id": "140",
          "vcodec": "none",
          "acodec": "mp4a.40.2"
        }
      ]
    }
    """
}
