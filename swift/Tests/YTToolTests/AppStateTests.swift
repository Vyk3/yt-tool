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

    func testMapsBilibiliPreconditionToNeedsCookiesWhenNoCookiesConfigured() {
        let state = AppState(defaults: freshDefaults())
        let error = AppError(
            message: "yt-dlp probe failed.",
            recoverySuggestion: "HTTP Error 412: Precondition Failed"
        )

        let mapped = state.mapYtDlpError(
            error,
            url: "https://www.bilibili.com/video/BV123",
            cookiesFilePath: nil
        )

        XCTAssertEqual(mapped.kind, .needsCookies)
        XCTAssertEqual(mapped.message, Loc.needsCookiesMessage(.english))
        XCTAssertEqual(mapped.recoverySuggestion, Loc.needsCookiesSuggestion(.english))
    }

    func testMapsBilibiliPreconditionToCookieExpiredWhenCookiesConfigured() {
        let state = AppState(defaults: freshDefaults())
        let error = AppError(
            message: "yt-dlp probe failed.",
            recoverySuggestion: "Precondition Failed"
        )

        let mapped = state.mapYtDlpError(
            error,
            url: "https://www.bilibili.com/video/BV123",
            cookiesFilePath: "/tmp/cookies.txt"
        )

        XCTAssertEqual(mapped.kind, .cookieExpired)
        XCTAssertEqual(mapped.message, Loc.cookieExpiredMessage(.english))
        XCTAssertEqual(mapped.recoverySuggestion, Loc.cookieExpiredSuggestion(.english))
    }

    func testMapsBilibiliHttpStatus412ToNeedsCookiesWhenNoCookiesConfigured() {
        let state = AppState(defaults: freshDefaults())
        let error = AppError(
            message: "yt-dlp probe failed.",
            recoverySuggestion: "Request failed with status 412"
        )

        let mapped = state.mapYtDlpError(
            error,
            url: "https://www.bilibili.com/video/BV123",
            cookiesFilePath: nil
        )

        XCTAssertEqual(mapped.kind, .needsCookies)
        XCTAssertEqual(mapped.message, Loc.needsCookiesMessage(.english))
        XCTAssertEqual(mapped.recoverySuggestion, Loc.needsCookiesSuggestion(.english))
    }

    func testKeepsBare412ErrorUnchangedForBilibiliURL() {
        let state = AppState(defaults: freshDefaults())
        let error = AppError(
            message: "yt-dlp probe failed.",
            recoverySuggestion: "format 412 is unavailable"
        )

        let mapped = state.mapYtDlpError(
            error,
            url: "https://www.bilibili.com/video/BV123",
            cookiesFilePath: nil
        )

        XCTAssertEqual(mapped, error)
    }

    func testKeepsPreconditionErrorUnchangedForNonBilibiliURL() {
        let state = AppState(defaults: freshDefaults())
        let error = AppError(
            message: "yt-dlp probe failed.",
            recoverySuggestion: "HTTP Error 412: Precondition Failed"
        )

        let mapped = state.mapYtDlpError(
            error,
            url: "https://www.youtube.com/watch?v=P5yHEKqx86U",
            cookiesFilePath: nil
        )

        XCTAssertEqual(mapped, error)
    }

    func testProbeKeepsInvalidCookiesPathErrorForBilibiliURL() async throws {
        let state = AppState(defaults: freshDefaults())
        state.inputURL = "https://www.bilibili.com/video/BV123"
        state.cookiesFilePath = "/tmp/yttool-missing-\(UUID().uuidString).txt"

        state.probe()
        let error = try await waitForProbeFailure(in: state)

        XCTAssertEqual(error.kind, .general)
        XCTAssertEqual(error.message, "Cookies file path is invalid.")
        XCTAssertEqual(error.recoverySuggestion, "Use an existing cookies file path.")
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
        state.playlistConfig.mode = .wholePlaylistBestVideo
        state.selectedOutputDirectory = FileManager.default.temporaryDirectory

        XCTAssertTrue(state.canDownload)
    }

    func testCanDownloadAllowsFallbackWhenProbeSucceedsWithNoSelectableFormats() {
        let state = AppState(defaults: freshDefaults())
        state.inputURL = "https://www.youtube.com/watch?v=P5yHEKqx86U"
        state.selectedOutputDirectory = FileManager.default.temporaryDirectory
        state.probeState = .success(
            MediaInfo(
                title: "Sample",
                duration: nil,
                webpageURL: "https://www.youtube.com/watch?v=P5yHEKqx86U",
                thumbnailURL: nil,
                viewCount: nil,
                uploader: nil,
                uploadDate: nil,
                videoFormats: [],
                audioFormats: [],
                subtitleTracks: [],
                autoSubtitleTracks: []
            )
        )

        XCTAssertTrue(state.hasNoSelectableFormatsAfterProbe)
        XCTAssertTrue(state.canDownload)
    }

    func testCanDownloadFallbackStillRequiresOutputDirectory() {
        let state = AppState(defaults: freshDefaults())
        state.inputURL = "https://www.youtube.com/watch?v=P5yHEKqx86U"
        state.probeState = .success(
            MediaInfo(
                title: "Sample",
                duration: nil,
                webpageURL: "https://www.youtube.com/watch?v=P5yHEKqx86U",
                thumbnailURL: nil,
                viewCount: nil,
                uploader: nil,
                uploadDate: nil,
                videoFormats: [],
                audioFormats: [],
                subtitleTracks: [],
                autoSubtitleTracks: []
            )
        )

        XCTAssertTrue(state.hasNoSelectableFormatsAfterProbe)
        XCTAssertFalse(state.canDownload)
    }

    func testNonPlaylistURLResetsPlaylistModeToOnlyFirstItem() {
        let state = AppState(defaults: freshDefaults())

        state.inputURL = "https://www.youtube.com/watch?v=P5yHEKqx86U&list=PL123"
        state.playlistConfig.mode = .wholePlaylistBestAudio
        state.inputURL = "https://www.youtube.com/watch?v=P5yHEKqx86U"

        XCTAssertEqual(state.playlistConfig.mode, .onlyFirstItem)
    }

    func testWholePlaylistModeSkipsSizeEstimate() {
        let state = AppState(defaults: freshDefaults())
        state.inputURL = "https://www.youtube.com/watch?v=P5yHEKqx86U&list=PL123"
        state.playlistConfig.mode = .wholePlaylistBestVideo

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

    func testShowsPlaylistVideoQualityStrategyOnlyForWholePlaylistVideo() {
        let state = AppState(defaults: freshDefaults())

        state.inputURL = "https://www.youtube.com/watch?v=P5yHEKqx86U&list=PL123"
        XCTAssertFalse(state.showsPlaylistVideoQualityStrategy)

        state.playlistConfig.mode = .wholePlaylistBestVideo
        XCTAssertTrue(state.showsPlaylistVideoQualityStrategy)

        state.playlistConfig.mode = .wholePlaylistBestAudio
        XCTAssertFalse(state.showsPlaylistVideoQualityStrategy)
    }

    func testSwitchingAwayFromWholePlaylistVideoResetsQualityStrategy() {
        let state = AppState(defaults: freshDefaults())

        state.inputURL = "https://www.youtube.com/watch?v=P5yHEKqx86U&list=PL123"
        state.playlistConfig.mode = .wholePlaylistBestVideo
        state.playlistConfig.videoQualityStrategy = .preferHigherQuality

        state.playlistConfig.mode = .wholePlaylistBestAudio

        XCTAssertEqual(state.playlistConfig.videoQualityStrategy, .bestCompatibility)
    }

    func testShowsPlaylistAudioQualityStrategyOnlyForWholePlaylistAudio() {
        let state = AppState(defaults: freshDefaults())

        state.inputURL = "https://www.youtube.com/watch?v=P5yHEKqx86U&list=PL123"
        XCTAssertFalse(state.showsPlaylistAudioQualityStrategy)

        state.playlistConfig.mode = .wholePlaylistBestAudio
        XCTAssertTrue(state.showsPlaylistAudioQualityStrategy)

        state.playlistConfig.mode = .wholePlaylistBestVideo
        XCTAssertFalse(state.showsPlaylistAudioQualityStrategy)
    }

    func testSwitchingAwayFromWholePlaylistAudioResetsAudioQualityStrategy() {
        let state = AppState(defaults: freshDefaults())

        state.inputURL = "https://www.youtube.com/watch?v=P5yHEKqx86U&list=PL123"
        state.playlistConfig.mode = .wholePlaylistBestAudio
        state.playlistConfig.audioQualityStrategy = .higherQuality

        state.playlistConfig.mode = .wholePlaylistBestVideo

        XCTAssertEqual(state.playlistConfig.audioQualityStrategy, .moreCompatible)
    }

    func testWholePlaylistManualSubtitleTrackUsesLanguage() throws {
        let state = AppState(defaults: freshDefaults())
        state.inputURL = "https://www.youtube.com/watch?v=P5yHEKqx86U&list=PL123"
        state.playlistConfig.mode = .wholePlaylistBestVideo
        state.playlistConfig.subtitleMode = .manual
        state.playlistConfig.subtitleLanguage = "en"

        let track = try state.wholePlaylistSubtitleTrackOrThrow()

        XCTAssertNotNil(track)
        XCTAssertEqual(track?.lang, "en")
        XCTAssertEqual(track?.isAuto, false)
    }

    func testWholePlaylistAutoSubtitleTrackUsesLanguage() throws {
        let state = AppState(defaults: freshDefaults())
        state.inputURL = "https://www.youtube.com/watch?v=P5yHEKqx86U&list=PL123"
        state.playlistConfig.mode = .wholePlaylistBestAudio
        state.playlistConfig.subtitleMode = .auto
        state.playlistConfig.subtitleLanguage = "zh-Hans"

        let track = try state.wholePlaylistSubtitleTrackOrThrow()

        XCTAssertNotNil(track)
        XCTAssertEqual(track?.lang, "zh-Hans")
        XCTAssertEqual(track?.isAuto, true)
    }

    func testWholePlaylistSubtitleTrackRequiresLanguageWhenEnabled() {
        let state = AppState(defaults: freshDefaults())
        state.inputURL = "https://www.youtube.com/watch?v=P5yHEKqx86U&list=PL123"
        state.playlistConfig.mode = .wholePlaylistBestAudio
        state.playlistConfig.subtitleMode = .manual
        state.playlistConfig.subtitleLanguage = "  "

        XCTAssertThrowsError(try state.wholePlaylistSubtitleTrackOrThrow())
    }

    func testWholePlaylistFixedSegmentAddsDownloadSectionsArgument() throws {
        let state = AppState(defaults: freshDefaults())
        state.inputURL = "https://www.youtube.com/watch?v=P5yHEKqx86U&list=PL123"
        state.playlistConfig.mode = .wholePlaylistBestVideo
        state.playlistConfig.segmentMode = .fixedRange
        state.playlistConfig.segmentRange = "00:30-01:00"

        let args = try state.wholePlaylistArgumentsOrThrow()

        XCTAssertEqual(args, ["--download-sections", "*00:30-01:00"])
    }

    func testWholePlaylistFixedSegmentPreservesExplicitWildcardRange() throws {
        let state = AppState(defaults: freshDefaults())
        state.inputURL = "https://www.youtube.com/watch?v=P5yHEKqx86U&list=PL123"
        state.playlistConfig.mode = .wholePlaylistBestVideo
        state.playlistConfig.segmentMode = .fixedRange
        state.playlistConfig.segmentRange = "*00:30-01:00"

        let args = try state.wholePlaylistArgumentsOrThrow()

        XCTAssertEqual(args, ["--download-sections", "*00:30-01:00"])
    }

    func testPerItemFormatMappingParsesEntries() throws {
        let state = AppState(defaults: freshDefaults())
        state.inputURL = "https://www.youtube.com/watch?v=P5yHEKqx86U&list=PL123"
        state.playlistConfig.mode = .wholePlaylistBestVideo
        state.playlistConfig.formatMode = .perItemMapping
        state.playlistConfig.perItemFormatMap = "1=137+140;2=136+140"

        let parsed = try state.parsePerItemFormatSelectionsOrThrow()

        XCTAssertEqual(parsed.map(\.index), [1, 2])
        XCTAssertEqual(parsed.map(\.formatSelector), ["137+140", "136+140"])
    }

    func testPerItemFormatMappingRejectsMalformedEntry() {
        let state = AppState(defaults: freshDefaults())
        state.inputURL = "https://www.youtube.com/watch?v=P5yHEKqx86U&list=PL123"
        state.playlistConfig.mode = .wholePlaylistBestVideo
        state.playlistConfig.formatMode = .perItemMapping
        state.playlistConfig.perItemFormatMap = "bad-entry"

        XCTAssertThrowsError(try state.parsePerItemFormatSelectionsOrThrow())
    }

    func testPerItemMappingDisablesTranscodeForCombinedVideoAudioSelector() {
        let state = AppState(defaults: freshDefaults())
        let resolved = state.effectivePerItemAudioTranscodeFormat(
            formatSelector: "137+140",
            selectedFormat: .mp3
        )
        XCTAssertNil(resolved)
    }

    func testPerItemMappingKeepsTranscodeForAudioOnlySelector() {
        let state = AppState(defaults: freshDefaults())
        let resolved = state.effectivePerItemAudioTranscodeFormat(
            formatSelector: "140",
            selectedFormat: .m4a
        )
        XCTAssertEqual(resolved, .m4a)
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

    // MARK: - Import URLs

    func testImportURLsAppendsToEmpty() {
        let state = AppState(defaults: freshDefaults())
        state.queueInputURLs = ""
        let result = state.importURLs(from: "https://youtube.com/watch?v=a1\nhttps://vimeo.com/b1\nhttps://bilibili.com/video/BVc1")
        XCTAssertEqual(result.importedCount, 3)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(state.queueInputURLs, "https://youtube.com/watch?v=a1\nhttps://vimeo.com/b1\nhttps://bilibili.com/video/BVc1")
    }

    func testImportURLsDedupsAgainstExisting() {
        let state = AppState(defaults: freshDefaults())
        state.queueInputURLs = "https://youtube.com/watch?v=a1\nhttps://vimeo.com/b1"
        let result = state.importURLs(from: "https://vimeo.com/b1\nhttps://bilibili.com/video/BVc1")
        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertTrue(state.queueInputURLs.contains("https://bilibili.com/video/BVc1"))
        XCTAssertEqual(
            state.queueInputURLs.components(separatedBy: "\n").filter { $0 == "https://vimeo.com/b1" }.count,
            1
        )
    }

    func testImportURLsDedupsWithinBatch() {
        let state = AppState(defaults: freshDefaults())
        state.queueInputURLs = ""
        let result = state.importURLs(from: "https://youtube.com/watch?v=a1\nhttps://youtube.com/watch?v=a1\nhttps://vimeo.com/b1")
        XCTAssertEqual(result.importedCount, 2)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(state.queueInputURLs, "https://youtube.com/watch?v=a1\nhttps://vimeo.com/b1")
    }

    func testImportURLsTrimsWhitespace() {
        let state = AppState(defaults: freshDefaults())
        state.queueInputURLs = ""
        let result = state.importURLs(from: "  https://youtube.com/watch?v=a1  \n  https://vimeo.com/b1  ")
        XCTAssertEqual(result.importedCount, 2)
        XCTAssertEqual(state.queueInputURLs, "https://youtube.com/watch?v=a1\nhttps://vimeo.com/b1")
    }

    func testImportURLsSkipsBlankLines() {
        let state = AppState(defaults: freshDefaults())
        state.queueInputURLs = ""
        let result = state.importURLs(from: "https://youtube.com/watch?v=a1\n\n\nhttps://vimeo.com/b1\n")
        XCTAssertEqual(result.importedCount, 2)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(state.queueInputURLs, "https://youtube.com/watch?v=a1\nhttps://vimeo.com/b1")
    }

    func testImportURLsEmptyInput() {
        let state = AppState(defaults: freshDefaults())
        state.queueInputURLs = "https://youtube.com/watch?v=exist"
        let result = state.importURLs(from: "")
        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(state.queueInputURLs, "https://youtube.com/watch?v=exist")
    }

    func testImportURLsAllDuplicates() {
        let state = AppState(defaults: freshDefaults())
        state.queueInputURLs = "https://youtube.com/watch?v=a1\nhttps://vimeo.com/b1"
        let result = state.importURLs(from: "https://youtube.com/watch?v=a1\nhttps://vimeo.com/b1")
        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(result.skippedCount, 2)
        XCTAssertEqual(state.queueInputURLs, "https://youtube.com/watch?v=a1\nhttps://vimeo.com/b1")
    }

    func testImportURLsPreservesExisting() {
        let state = AppState(defaults: freshDefaults())
        state.queueInputURLs = "https://youtube.com/watch?v=a1"
        let result = state.importURLs(from: "https://vimeo.com/b1")
        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(state.queueInputURLs, "https://youtube.com/watch?v=a1\nhttps://vimeo.com/b1")
    }

    func testImportURLsNoDoubleNewline() {
        let state = AppState(defaults: freshDefaults())
        state.queueInputURLs = "https://youtube.com/watch?v=a1\n"
        let result = state.importURLs(from: "https://vimeo.com/b1")
        XCTAssertEqual(result.importedCount, 1)
        let lines = state.queueInputURLs.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines, ["https://youtube.com/watch?v=a1", "https://vimeo.com/b1"])
    }

    func testImportURLsFiltersNonURLLines() {
        let state = AppState(defaults: freshDefaults())
        state.queueInputURLs = ""
        let result = state.importURLs(from: "My Favorite Videos\nhttps://youtube.com/watch?v=a1\nsome random text\nhttps://vimeo.com/b1")
        XCTAssertEqual(result.importedCount, 2)
        XCTAssertEqual(result.filteredCount, 2)
        XCTAssertEqual(state.queueInputURLs, "https://youtube.com/watch?v=a1\nhttps://vimeo.com/b1")
    }

    func testImportURLsAcceptsHTTPWithoutS() {
        let state = AppState(defaults: freshDefaults())
        state.queueInputURLs = ""
        let result = state.importURLs(from: "http://youtube.com/watch?v=legacy\nhttps://vimeo.com/modern")
        XCTAssertEqual(result.importedCount, 2)
        XCTAssertEqual(result.filteredCount, 0)
    }

    func testImportURLsFiltersCaseInsensitive() {
        let state = AppState(defaults: freshDefaults())
        state.queueInputURLs = ""
        let result = state.importURLs(from: "HTTPS://YOUTUBE.COM/watch?v=a1\nHttp://VIMEO.COM/b1")
        XCTAssertEqual(result.importedCount, 2)
        XCTAssertEqual(result.filteredCount, 0)
    }

    func testImportURLsAllNonURLContent() {
        let state = AppState(defaults: freshDefaults())
        state.queueInputURLs = ""
        let result = state.importURLs(from: "just some text\nanother line\n123")
        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(result.filteredCount, 3)
        XCTAssertEqual(state.queueInputURLs, "")
    }

    func testImportURLsRejectsUnsupportedHosts() {
        let state = AppState(defaults: freshDefaults())
        state.queueInputURLs = ""
        let result = state.importURLs(from: "https://example.com\nhttps://youtube.com/watch?v=ok\nhttps://random.org/page")
        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.unsupportedCount, 2)
        XCTAssertEqual(state.queueInputURLs, "https://youtube.com/watch?v=ok")
    }

    func testClearLocalDataCreatesBackupAndDoesNotDeleteExternalFiles() throws {
        let fixture = try makeLocalDataFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let state = fixture.state
        state.historyStore.append(fixture.historyEntry)
        state.subscriptionStore.add(fixture.subscription)

        let backupURL = try state.clearLocalData()

        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.appendingPathComponent("defaults.plist").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.historyURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.subscriptionsURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.userBinariesURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.outputDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.cookiesURL.path))
        XCTAssertTrue(state.historyStore.entries.isEmpty)
        XCTAssertTrue(state.subscriptionStore.subscriptions.isEmpty)
    }

    func testRestoreLocalDataRestoresBackupPayload() throws {
        let fixture = try makeLocalDataFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let state = fixture.state
        state.historyStore.append(fixture.historyEntry)
        state.subscriptionStore.add(fixture.subscription)

        let backupURL = try state.clearLocalData()
        try state.restoreLocalData(from: backupURL)

        XCTAssertEqual(state.selectedOutputDirectory?.path, fixture.outputDirectory.path)
        XCTAssertEqual(state.downloaderPreference, .aria2c)
        XCTAssertEqual(state.historyStore.entries.map(\.url), [fixture.historyEntry.url])
        XCTAssertEqual(state.subscriptionStore.subscriptions.map(\.channelID), [fixture.subscription.channelID])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.userBinariesURL.appendingPathComponent("yt-dlp").path))
    }

    private func freshDefaults() -> UserDefaults {
        let suiteName = "YTToolTests.\(#function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private struct LocalDataFixture {
        let root: URL
        let state: AppState
        let historyURL: URL
        let subscriptionsURL: URL
        let userBinariesURL: URL
        let outputDirectory: URL
        let cookiesURL: URL
        let historyEntry: DownloadHistoryEntry
        let subscription: ChannelSubscription
    }

    private func makeLocalDataFixture() throws -> LocalDataFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AppStateLocalData-\(UUID().uuidString)", isDirectory: true)
        let appData = root.appendingPathComponent("AppData", isDirectory: true)
        let outputDirectory = root.appendingPathComponent("Downloads", isDirectory: true)
        let cookiesURL = root.appendingPathComponent("cookies.txt")
        let userBinariesURL = root.appendingPathComponent("Binaries", isDirectory: true)
        try FileManager.default.createDirectory(at: appData, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userBinariesURL, withIntermediateDirectories: true)
        try Data("cookies".utf8).write(to: cookiesURL)
        let ytDlp = userBinariesURL.appendingPathComponent("yt-dlp")
        try Data("#!/bin/sh\n".utf8).write(to: ytDlp)

        let defaults = freshDefaults()
        defaults.set(outputDirectory.path, forKey: "selectedOutputDirectoryPath")
        defaults.set(DownloaderPreference.aria2c.rawValue, forKey: "downloaderPreference")
        defaults.set(Data("[]".utf8), forKey: SubscriptionPollingManager.newVideosKey)

        let historyURL = appData.appendingPathComponent("download_history.json")
        let subscriptionsURL = appData.appendingPathComponent("channel_subscriptions.json")
        let historyStore = DownloadHistoryStore(storageURL: historyURL)
        let subscriptionStore = ChannelSubscriptionStore(storageURL: subscriptionsURL)
        let state = AppState(
            defaults: defaults,
            historyStore: historyStore,
            subscriptionStore: subscriptionStore,
            userLocalBinariesDirectory: userBinariesURL
        )
        state.cookiesFilePath = cookiesURL.path

        let historyEntry = DownloadHistoryEntry(
            id: UUID(),
            url: "https://example.com/video",
            title: "Video",
            outputPath: outputDirectory.appendingPathComponent("video.mp4").path,
            dateCompleted: Date(),
            succeeded: true,
            estimatedSizeBytes: nil
        )
        let subscription = ChannelSubscription(
            id: UUID(),
            channelID: "UC_LOCAL",
            channelName: "Local",
            channelURL: "https://www.youtube.com/channel/UC_LOCAL",
            dateAdded: Date(),
            isEnabled: true,
            lastCheckedDate: nil,
            lastVideoID: nil
        )

        return LocalDataFixture(
            root: root,
            state: state,
            historyURL: historyURL,
            subscriptionsURL: subscriptionsURL,
            userBinariesURL: userBinariesURL,
            outputDirectory: outputDirectory,
            cookiesURL: cookiesURL,
            historyEntry: historyEntry,
            subscription: subscription
        )
    }

    private func waitForProbeFailure(in state: AppState) async throws -> AppError {
        for _ in 0 ..< 50 {
            if case let .failure(error) = state.probeState {
                return error
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Expected probe failure")
        throw AppError(message: "Missing probe failure")
    }
}
