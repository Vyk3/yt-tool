import XCTest
@testable import YTTool

final class BundledToolLocatorTests: XCTestCase {
    func testCandidateURLsPreferBundleAndProjectFallback() {
        let locator = BundledToolLocator(bundle: .main)

        let candidates = locator.candidateURLs(for: .ytDlp)

        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.contains { $0.path.contains("Resources/Binaries/yt-dlp") })
    }
}
