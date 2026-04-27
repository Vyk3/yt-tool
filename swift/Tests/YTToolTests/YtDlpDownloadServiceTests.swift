import XCTest
@testable import YTTool

final class YtDlpDownloadServiceTests: XCTestCase {
    func testWholePlaylistAudioOmitsNoPlaylistAndUsesAudioSelector() async throws {
        let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let resultFile = outputDirectory.appendingPathComponent("result.m4a")
        let ytDlp = try makeDownloadScript(resultFile: resultFile)
        let ffmpeg = try makeExecutableStub()
        let service = YtDlpDownloadService(
            locator: BundledToolLocator(overrides: [.ytDlp: ytDlp, .ffmpeg: ffmpeg]),
            runner: ProcessRunner()
        )

        let commandSink = ThreadSafeStringBox()
        for try await event in service.download(
            url: "https://www.youtube.com/watch?v=P5yHEKqx86U&list=PL123",
            videoFormatId: nil,
            audioFormatId: nil,
            outputDirectory: outputDirectory,
            playlistMode: .wholePlaylistBestAudio,
            onLog: { kind, message in
                if kind == .command {
                    commandSink.value = message
                }
            }
        ) {
            if case .completed(let result) = event {
                XCTAssertEqual(result.outputURL, outputDirectory)
            }
        }

        XCTAssertNotNil(commandSink.value)
        XCTAssertTrue(commandSink.value?.contains("-f ba/bestaudio/best") == true)
        XCTAssertFalse(commandSink.value?.contains("--no-playlist") == true)
    }

    func testOnlyFirstItemKeepsNoPlaylistAndSelectedFormats() async throws {
        let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let resultFile = outputDirectory.appendingPathComponent("result.mp4")
        let ytDlp = try makeDownloadScript(resultFile: resultFile)
        let ffmpeg = try makeExecutableStub()
        let service = YtDlpDownloadService(
            locator: BundledToolLocator(overrides: [.ytDlp: ytDlp, .ffmpeg: ffmpeg]),
            runner: ProcessRunner()
        )

        let commandSink = ThreadSafeStringBox()
        for try await _ in service.download(
            url: "https://www.youtube.com/watch?v=P5yHEKqx86U&list=PL123",
            videoFormatId: "137",
            audioFormatId: "140",
            outputDirectory: outputDirectory,
            playlistMode: .onlyFirstItem,
            onLog: { kind, message in
                if kind == .command {
                    commandSink.value = message
                }
            }
        ) {}

        XCTAssertNotNil(commandSink.value)
        XCTAssertTrue(commandSink.value?.contains("-f 137+140") == true)
        XCTAssertTrue(commandSink.value?.contains("--no-playlist") == true)
    }

    private func makeDownloadScript(resultFile: URL) throws -> URL {
        let contents = """
        #!/bin/sh
        touch "\(resultFile.path)"
        echo "\(resultFile.path)"
        """
        return try makeExecutableScript(contents)
    }

    private func makeExecutableStub() throws -> URL {
        try makeExecutableScript(
            """
            #!/bin/sh
            exit 0
            """
        )
    }

    private func makeExecutableScript(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}

private final class ThreadSafeStringBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: String?

    var value: String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}
