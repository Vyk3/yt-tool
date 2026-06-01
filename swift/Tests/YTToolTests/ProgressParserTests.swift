import XCTest
@testable import YTTool

final class ProgressParserTests: XCTestCase {
    // MARK: - parse(line:)

    func testParsesTypicalProgressLine() throws {
        let parser = ProgressParser()
        let result = try XCTUnwrap(parser.parse(line: "[download]  25.3% of    6.48MiB at    1.24MiB/s ETA 00:03"))

        XCTAssertEqual(result.percentComplete, 0.253, accuracy: 0.001)
        XCTAssertTrue(result.summaryLine.contains("25.3%"))
    }

    func testParses100Percent() throws {
        let parser = ProgressParser()
        let result = try XCTUnwrap(parser.parse(line: "[download] 100% of    6.48MiB in 00:05"))

        XCTAssertEqual(result.percentComplete, 1.0)
    }

    func testClampsAbove100() throws {
        let parser = ProgressParser()
        let result = try XCTUnwrap(parser.parse(line: "[download] 150.0% of something"))

        XCTAssertEqual(result.percentComplete, 1.0)
    }

    func testReturnsNilForNonProgressLine() {
        let parser = ProgressParser()
        XCTAssertNil(parser.parse(line: "[info] Extracting URL: https://example.com"))
        XCTAssertNil(parser.parse(line: "WARNING: some warning"))
        XCTAssertNil(parser.parse(line: ""))
    }

    func testStripsDownloadPrefixFromSummary() throws {
        let parser = ProgressParser()
        let result = try XCTUnwrap(parser.parse(line: "[download]  50.0% of 10MiB at 2MiB/s ETA 00:02"))

        XCTAssertFalse(result.summaryLine.contains("[download]"))
    }

    // MARK: - parse(chunk:)

    func testParsesMultiLineChunk() throws {
        var parser = ProgressParser()
        let chunk = "[download]  10.0% of 5MiB\n[download]  20.0% of 5MiB\n"
        let result = try XCTUnwrap(parser.parse(chunk: chunk))

        XCTAssertEqual(result.percentComplete, 0.2, accuracy: 0.001)
    }

    func testBuffersIncompleteLines() throws {
        var parser = ProgressParser()

        let result1 = parser.parse(chunk: "[download]  30.0% of 5Mi")
        XCTAssertNil(result1)

        let result2 = try XCTUnwrap(parser.parse(chunk: "B at 1MiB/s ETA 00:03\n"))
        XCTAssertEqual(result2.percentComplete, 0.3, accuracy: 0.001)
    }

    func testChunkEndingWithNewlineDoesNotBuffer() throws {
        var parser = ProgressParser()
        let result = try XCTUnwrap(parser.parse(chunk: "[download]  40.0% of 5MiB\n"))

        XCTAssertEqual(result.percentComplete, 0.4, accuracy: 0.001)
    }

    func testMixedProgressAndInfoLines() throws {
        var parser = ProgressParser()
        let chunk = "[info] Starting download\n[download]  60.0% of 5MiB\n"
        let result = try XCTUnwrap(parser.parse(chunk: chunk))

        XCTAssertEqual(result.percentComplete, 0.6, accuracy: 0.001)
    }

    // MARK: - consume(chunk:onNonProgressLine:)

    func testConsumeReportsNonProgressLines() throws {
        var parser = ProgressParser()
        var nonProgressLines: [String] = []

        let chunk = "[info] Extracting URL\n[download]  70.0% of 5MiB\n[merger] Merging formats\n"
        let result = try XCTUnwrap(parser.consume(chunk: chunk) { line in
            nonProgressLines.append(line)
        })

        XCTAssertEqual(result.percentComplete, 0.7, accuracy: 0.001)
        XCTAssertEqual(nonProgressLines, ["[info] Extracting URL", "[merger] Merging formats"])
    }

    func testConsumeSkipsEmptyLines() {
        var parser = ProgressParser()
        var nonProgressLines: [String] = []

        let chunk = "\n\n[download]  80.0% of 5MiB\n\n"
        let result = parser.consume(chunk: chunk) { line in
            nonProgressLines.append(line)
        }

        XCTAssertNotNil(result)
        XCTAssertTrue(nonProgressLines.isEmpty)
    }

    func testConsumeBuffersAcrossCalls() {
        var parser = ProgressParser()
        var lines: [String] = []

        let result1 = parser.consume(chunk: "[info] Partial me") { lines.append($0) }
        XCTAssertNil(result1)
        XCTAssertTrue(lines.isEmpty)

        let result2 = parser.consume(chunk: "ssage\n[download]  90.0% of 5MiB\n") { lines.append($0) }
        XCTAssertNotNil(result2)
        XCTAssertEqual(lines, ["[info] Partial message"])
    }
}
