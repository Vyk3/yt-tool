import XCTest
@testable import YTTool

@MainActor
final class AppLogTests: XCTestCase {
    func testAppendLogKeepsRecentEntriesOnly() {
        let state = AppState(defaults: freshDefaults())

        for index in 0..<300 {
            state.appendLog(scope: .probe, level: .info, message: "entry-\(index)")
        }

        XCTAssertEqual(state.logs.count, 250)
        XCTAssertEqual(state.logs.first?.message, "entry-50")
        XCTAssertEqual(state.logs.last?.message, "entry-299")
    }

    func testAppendLogTrimsWhitespaceAndSkipsEmptyMessages() {
        let state = AppState(defaults: freshDefaults())

        state.appendLog(scope: .app, level: .info, message: "  hello world  ")
        state.appendLog(scope: .app, level: .info, message: "   \n\t  ")

        XCTAssertEqual(state.logs.map(\.message), ["hello world"])
    }

    private func freshDefaults() -> UserDefaults {
        let suiteName = "YTToolTests.Logs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
