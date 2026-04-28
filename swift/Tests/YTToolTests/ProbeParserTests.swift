import XCTest
@testable import YTTool

final class ProbeParserTests: XCTestCase {
    func testProgressParserConsumeRecognizesProgressLinesFromStdoutChunks() {
        var parser = ProgressParser()
        var loggedLines: [String] = []

        let progress = parser.consume(
            chunk: """
            [download]  17.7% of  127.53MiB at    2.16MiB/s ETA 00:56 (frag 19/113)
            /Users/koa/Downloads/example.mp4

            """,
            onNonProgressLine: { loggedLines.append($0) }
        )

        XCTAssertNotNil(progress)
        XCTAssertEqual(progress!.percentComplete, 0.177, accuracy: 0.0001)
        XCTAssertEqual(
            progress!.summaryLine,
            "17.7% of  127.53MiB at    2.16MiB/s ETA 00:56 (frag 19/113)"
        )
        XCTAssertEqual(loggedLines, ["/Users/koa/Downloads/example.mp4"])
    }

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

    func testParseSubtitleTracks() throws {
        let info = try ProbeParser().parse(Self.subtitleProbeJSON.data(using: .utf8)!)

        XCTAssertEqual(info.subtitleTracks.map(\.displayName), ["English", "Japanese"])
        XCTAssertEqual(info.subtitleTracks.first(where: { $0.lang == "en" })?.label, "English")
        XCTAssertEqual(info.subtitleTracks.first(where: { $0.lang == "en" })?.isAuto, false)

        XCTAssertEqual(info.autoSubtitleTracks.map(\.lang).sorted(), ["fr"])
        XCTAssertEqual(info.autoSubtitleTracks.first?.label, "French")
        XCTAssertEqual(info.autoSubtitleTracks.first?.isAuto, true)
    }

    func testSubtitleTracksAreSortedByDisplayName() throws {
        let info = try ProbeParser().parse(Self.unsortedSubtitleProbeJSON.data(using: .utf8)!)
        XCTAssertEqual(info.subtitleTracks.map(\.displayName), ["Arabic", "English", "Zulu"])
    }

    func testParseLiveChatIsFiltered() throws {
        let info = try ProbeParser().parse(Self.liveChatProbeJSON.data(using: .utf8)!)

        XCTAssertFalse(info.subtitleTracks.contains(where: { $0.lang == "live_chat" }))
        XCTAssertFalse(info.autoSubtitleTracks.contains(where: { $0.lang == "live_chat" }))
        XCTAssertEqual(info.subtitleTracks.map(\.lang), ["en"])
    }

    func testParseNoSubtitleKeysReturnsEmpty() throws {
        let info = try ProbeParser().parse(Self.normalProbeJSON.data(using: .utf8)!)

        XCTAssertTrue(info.subtitleTracks.isEmpty)
        XCTAssertTrue(info.autoSubtitleTracks.isEmpty)
    }

    func testSubtitleTrackIdIsNamespaced() {
        let manual = SubtitleTrack(lang: "en", label: "English", isAuto: false)
        let auto = SubtitleTrack(lang: "en", label: "English", isAuto: true)
        XCTAssertNotEqual(manual.id, auto.id)
        XCTAssertEqual(manual.id, "manual.en")
        XCTAssertEqual(auto.id, "auto.en")
    }

    func testSubtitleDisplayNameFallsBackToLang() {
        let track = SubtitleTrack(lang: "zh-Hans", label: "", isAuto: false)
        XCTAssertEqual(track.displayName, "zh-Hans")
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

    private static let subtitleProbeJSON = """
    {
      "title": "Subtitle Test",
      "webpage_url": "https://example.com/watch?v=sub",
      "formats": [],
      "subtitles": {
        "en": [{"name": "English", "ext": "vtt"}],
        "ja": [{"name": "Japanese", "ext": "vtt"}]
      },
      "automatic_captions": {
        "fr": [{"name": "French", "ext": "vtt"}]
      }
    }
    """

    private static let liveChatProbeJSON = """
    {
      "title": "Live Chat Test",
      "webpage_url": "https://example.com/watch?v=live",
      "formats": [],
      "subtitles": {
        "en": [{"name": "English", "ext": "vtt"}],
        "live_chat": [{"name": "Live chat replay", "ext": "json"}]
      },
      "automatic_captions": {
        "live_chat": [{"name": "Live chat replay", "ext": "json"}]
      }
    }
    """

    private static let unsortedSubtitleProbeJSON = """
    {
      "title": "Subtitle Sort Test",
      "webpage_url": "https://example.com/watch?v=sort",
      "formats": [],
      "subtitles": {
        "zu": [{"name": "Zulu", "ext": "vtt"}],
        "en": [{"name": "English", "ext": "vtt"}],
        "ar": [{"name": "Arabic", "ext": "vtt"}]
      }
    }
    """
}
