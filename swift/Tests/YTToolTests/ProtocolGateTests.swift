import XCTest
@testable import YTTool

private final class StubProcessRunner: ProcessRunning, @unchecked Sendable {
    var streamCallCount = 0

    func stream(_: ProcessConfiguration) -> AsyncThrowingStream<ProcessEvent, Error> {
        streamCallCount += 1
        return AsyncThrowingStream { continuation in
            continuation.yield(.started(pid: 0))
            continuation.yield(.finished(ProcessResult(
                command: [],
                stdout: "/tmp/stub-output.mp4",
                stderr: "",
                exitCode: 0
            )))
            continuation.finish()
        }
    }

    func cancel(gracePeriod _: Duration) async throws {}
}

private final class LogSink: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(ServiceLogKind, String)] = []

    func append(_ kind: ServiceLogKind, _ message: String) {
        lock.lock()
        storage.append((kind, message))
        lock.unlock()
    }

    var entries: [(ServiceLogKind, String)] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private func stubLocator() throws -> BundledToolLocator {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("protocol-gate-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let script = "#!/bin/sh\nexit 0\n"
    for name in ["yt-dlp", "ffmpeg"] {
        let path = dir.appendingPathComponent(name)
        try script.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: path.path
        )
    }
    return BundledToolLocator(overrides: [
        .ytDlp: dir.appendingPathComponent("yt-dlp"),
        .ffmpeg: dir.appendingPathComponent("ffmpeg"),
    ])
}

final class ProtocolGateTests: XCTestCase {
    // P1: no --download-sections → gate does not fire, download proceeds even with nil protocol
    func testNoDownloadSectionsPassesWithNilProtocol() async throws {
        let stub = StubProcessRunner()
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let service = try YtDlpDownloadService(locator: stubLocator(), runner: stub)
        for try await _ in service.download(
            url: "https://example.com/video",
            videoFormatId: "137",
            audioFormatId: "140",
            selectedProtocols: [nil],
            outputDirectory: outputDir
        ) {}
        XCTAssertEqual(stub.streamCallCount, 1, "Process should launch without --download-sections")
    }

    // P8: --download-sections + empty selectedProtocols → defense-in-depth warning
    func testDownloadSectionsNoMetadataEmitsWarning() async throws {
        let stub = StubProcessRunner()
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let service = try YtDlpDownloadService(locator: stubLocator(), runner: stub)
        let sink = LogSink()
        for try await _ in service.download(
            url: "https://example.com/video",
            videoFormatId: nil,
            audioFormatId: nil,
            managedArguments: ["--download-sections", "*0:00:00-0:01:00"],
            selectedProtocols: [],
            outputDirectory: outputDir,
            onLog: { kind, message in
                if kind == .warning { sink.append(kind, message) }
            }
        ) {}
        XCTAssertEqual(stub.streamCallCount, 1, "Process should launch for defense-in-depth path")
        XCTAssertTrue(sink.entries.contains(where: { $0.1.contains("compiled protocol") }),
                      "Should emit compiled protocol warning")
    }

    /// Rejected protocol with --download-sections → process not launched
    func testDownloadSectionsRejectedProtocolThrows() async throws {
        let stub = StubProcessRunner()
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let service = try YtDlpDownloadService(locator: stubLocator(), runner: stub)
        do {
            for try await _ in service.download(
                url: "https://example.com/video",
                videoFormatId: "137",
                audioFormatId: "140",
                managedArguments: ["--download-sections", "*0:00:00-0:01:00"],
                selectedProtocols: ["rtmp"],
                outputDirectory: outputDir
            ) {}
            XCTFail("Should throw for rejected protocol")
        } catch {
            XCTAssertEqual(stub.streamCallCount, 0, "Process should NOT launch for rejected protocol")
        }
    }

    /// --download-sections via extraOptions + rejected protocol
    func testDownloadSectionsViaExtraOptionsRejectedProtocol() async throws {
        let stub = StubProcessRunner()
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let service = try YtDlpDownloadService(locator: stubLocator(), runner: stub)
        let extraOpts = try parseExtraOptions("--download-sections *0:00:00-0:01:00")
        do {
            for try await _ in service.download(
                url: "https://example.com/video",
                videoFormatId: "137",
                audioFormatId: "140",
                extraOptions: extraOpts,
                selectedProtocols: ["http_dash_segments"],
                outputDirectory: outputDir
            ) {}
            XCTFail("Should throw for rejected protocol via extra options")
        } catch {
            XCTAssertEqual(stub.streamCallCount, 0)
        }
    }

    /// Allowed protocol with --download-sections → process launches
    func testDownloadSectionsAllowedProtocolProceeds() async throws {
        let stub = StubProcessRunner()
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let service = try YtDlpDownloadService(locator: stubLocator(), runner: stub)
        for try await _ in service.download(
            url: "https://example.com/video",
            videoFormatId: "137",
            audioFormatId: "140",
            managedArguments: ["--download-sections", "*0:00:00-0:01:00"],
            selectedProtocols: ["https"],
            outputDirectory: outputDir
        ) {}
        XCTAssertEqual(stub.streamCallCount, 1, "Process should launch for allowed protocol")
    }

    /// nil protocol with --download-sections → rejected (unknown protocol)
    func testDownloadSectionsNilProtocolRejected() async throws {
        let stub = StubProcessRunner()
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let service = try YtDlpDownloadService(locator: stubLocator(), runner: stub)
        do {
            for try await _ in service.download(
                url: "https://example.com/video",
                videoFormatId: "137",
                audioFormatId: "140",
                managedArguments: ["--download-sections", "*0:00:00-0:01:00"],
                selectedProtocols: [nil],
                outputDirectory: outputDir
            ) {}
            XCTFail("Should throw for nil protocol with --download-sections")
        } catch {
            XCTAssertEqual(stub.streamCallCount, 0)
        }
    }
}
