import XCTest
@testable import YTTool

@MainActor
final class AppStateTests: XCTestCase {
    func testRestoresPersistedOutputDirectory() {
        let defaults = freshDefaults()
        defaults.set("/tmp/yttool-output", forKey: "selectedOutputDirectoryPath")

        let state = AppState(defaults: defaults)

        XCTAssertEqual(state.selectedOutputDirectory?.path(percentEncoded: false), "/tmp/yttool-output")
    }

    func testPersistsUpdatedOutputDirectory() {
        let defaults = freshDefaults()
        let state = AppState(defaults: defaults)

        state.selectedOutputDirectory = URL(fileURLWithPath: "/tmp/yttool-updated")

        XCTAssertEqual(defaults.string(forKey: "selectedOutputDirectoryPath"), "/tmp/yttool-updated")
    }

    private func freshDefaults() -> UserDefaults {
        let suiteName = "YTToolTests.\(#function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
