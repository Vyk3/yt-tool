import XCTest
@testable import YTTool

@MainActor
final class AppStateTests: XCTestCase {
    func testRestoresPersistedOutputDirectory() {
        let defaults = freshDefaults()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defaults.set(directory.path(percentEncoded: false), forKey: "selectedOutputDirectoryPath")
        let expectedDirectory = URL(fileURLWithPath: directory.path(percentEncoded: false), isDirectory: true)

        let state = AppState(defaults: defaults)

        XCTAssertEqual(
            state.selectedOutputDirectory?.path(percentEncoded: false),
            expectedDirectory.path(percentEncoded: false)
        )
    }

    func testPersistsUpdatedOutputDirectory() {
        let defaults = freshDefaults()
        let state = AppState(defaults: defaults)

        state.selectedOutputDirectory = URL(fileURLWithPath: "/tmp/yttool-updated")

        XCTAssertEqual(defaults.string(forKey: "selectedOutputDirectoryPath"), "/tmp/yttool-updated")
    }

    func testIgnoresPersistedOutputDirectoryWhenFolderIsMissing() {
        let defaults = freshDefaults()
        defaults.set("/tmp/yttool-missing-\(UUID().uuidString)", forKey: "selectedOutputDirectoryPath")

        let state = AppState(defaults: defaults)

        XCTAssertNil(state.selectedOutputDirectory)
        XCTAssertNil(defaults.string(forKey: "selectedOutputDirectoryPath"))
    }

    func testBeginProbeAttemptInvalidatesOlderAttempt() {
        let state = AppState(defaults: freshDefaults())

        let firstAttempt = state.beginProbeAttempt()
        let secondAttempt = state.beginProbeAttempt()

        XCTAssertFalse(state.isCurrentProbeAttempt(firstAttempt))
        XCTAssertTrue(state.isCurrentProbeAttempt(secondAttempt))
    }

    func testCancelDownloadInvalidatesActiveAttempt() {
        let state = AppState(defaults: freshDefaults())

        let attempt = state.beginDownloadAttempt()
        state.cancelDownload()

        XCTAssertFalse(state.isCurrentDownloadAttempt(attempt))
    }

    func testEstimatedDownloadSizeSumsSelectedFormats() {
        let state = AppState(defaults: freshDefaults())

        let video = VideoFormat(
            id: "137",
            resolution: "1080p",
            codec: "avc1",
            fps: 30,
            bitrateKbps: 1000,
            fileSizeBytes: 200,
            note: "no audio"
        )
        let audio = AudioFormat(
            id: "140",
            codec: "mp4a",
            bitrateKbps: 128,
            fileSizeBytes: 50,
            note: "medium"
        )

        XCTAssertEqual(state.estimatedDownloadSizeBytes(video: video, audio: audio), 250)
    }

    func testWholePlaylistModeAllowsDownloadWithoutProbeSelection() {
        let state = AppState(defaults: freshDefaults())

        state.inputURL = "https://www.youtube.com/watch?v=P5yHEKqx86U&list=PL123"
        state.playlistMode = .wholePlaylistBestVideo
        state.selectedOutputDirectory = FileManager.default.temporaryDirectory

        XCTAssertTrue(state.canDownload)
    }

    func testNonPlaylistURLResetsPlaylistModeToOnlyFirstItem() {
        let state = AppState(defaults: freshDefaults())

        state.inputURL = "https://www.youtube.com/watch?v=P5yHEKqx86U&list=PL123"
        state.playlistMode = .wholePlaylistBestAudio
        state.inputURL = "https://www.youtube.com/watch?v=P5yHEKqx86U"

        XCTAssertEqual(state.playlistMode, .onlyFirstItem)
    }

    func testWholePlaylistModeSkipsSizeEstimate() {
        let state = AppState(defaults: freshDefaults())
        state.inputURL = "https://www.youtube.com/watch?v=P5yHEKqx86U&list=PL123"
        state.playlistMode = .wholePlaylistBestVideo

        let video = VideoFormat(
            id: "137",
            resolution: "1080p",
            codec: "avc1",
            fps: 30,
            bitrateKbps: 1000,
            fileSizeBytes: 200,
            note: "no audio"
        )

        XCTAssertNil(state.estimatedDownloadSizeBytes(video: video, audio: nil))
    }

    func testRefreshFFmpegWarningClearsWhenAllToolsExist() throws {
        let state = AppState(defaults: freshDefaults())
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let ffmpegURL = tempDir.appendingPathComponent("ffmpeg")
        let ffprobeURL = tempDir.appendingPathComponent("ffprobe")
        FileManager.default.createFile(atPath: ffmpegURL.path, contents: Data("#!/bin/sh\n".utf8))
        FileManager.default.createFile(atPath: ffprobeURL.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffmpegURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffprobeURL.path)

        let locator = BundledToolLocator(
            bundle: .main,
            overrides: [.ffmpeg: ffmpegURL, .ffprobe: ffprobeURL]
        )

        state.refreshFFmpegWarning(locator: locator)

        XCTAssertNil(state.ffmpegWarningMessage)
    }

    func testRefreshFFmpegWarningSetsMessageWhenToolMissing() throws {
        let state = AppState(defaults: freshDefaults())
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let ffmpegURL = tempDir.appendingPathComponent("ffmpeg")
        FileManager.default.createFile(atPath: ffmpegURL.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffmpegURL.path)

        let locator = BundledToolLocator(
            bundle: .main,
            overrides: [.ffmpeg: ffmpegURL, .ffprobe: tempDir.appendingPathComponent("ffprobe-missing")]
        )

        state.refreshFFmpegWarning(locator: locator)

        XCTAssertNotNil(state.ffmpegWarningMessage)
        XCTAssertTrue(state.ffmpegWarningMessage?.contains("ffprobe is missing") == true)
    }

    private func freshDefaults() -> UserDefaults {
        let suiteName = "YTToolTests.\(#function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
