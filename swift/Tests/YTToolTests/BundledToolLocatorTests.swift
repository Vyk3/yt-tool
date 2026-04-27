import XCTest
@testable import YTTool

final class BundledToolLocatorTests: XCTestCase {
    func testCandidateURLsPreferBundleAndProjectFallback() {
        let locator = BundledToolLocator(bundle: .main)

        let candidates = locator.candidateURLs(for: .ytDlp)

        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.contains { $0.path.contains("Resources/Binaries/yt-dlp") })
    }

    func testMissingToolsReturnsOnlyUnavailableEntries() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let ffmpegURL = tempDir.appendingPathComponent("ffmpeg")
        FileManager.default.createFile(atPath: ffmpegURL.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffmpegURL.path)

        let locator = BundledToolLocator(
            bundle: .main,
            overrides: [
                .ffmpeg: ffmpegURL,
                .ffprobe: tempDir.appendingPathComponent("ffprobe-missing"),
            ]
        )

        let missing = locator.missingTools([.ffmpeg, .ffprobe])

        XCTAssertEqual(missing, [.ffprobe])
    }

    func testCandidateURLsSkipProjectFallbackForAppBundle() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let appRoot = tempDir.appendingPathComponent("Fake.app")
        let contents = appRoot.appendingPathComponent("Contents")
        let resources = contents.appendingPathComponent("Resources")

        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let plist = contents.appendingPathComponent("Info.plist")
        let plistData = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>local.koa.fake</string>
            <key>CFBundleName</key>
            <string>Fake</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
        </dict>
        </plist>
        """.data(using: .utf8)!
        FileManager.default.createFile(atPath: plist.path, contents: plistData)

        let bundle = try XCTUnwrap(Bundle(url: appRoot))
        let locator = BundledToolLocator(bundle: bundle)

        let candidates = locator.candidateURLs(for: .ffprobe)

        XCTAssertEqual(candidates.count, 1)
        XCTAssertTrue(candidates[0].path.contains("Fake.app/Contents/Resources/Binaries/ffprobe"))
    }
}
