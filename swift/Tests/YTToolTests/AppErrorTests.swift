import XCTest
@testable import YTTool

final class AppErrorTests: XCTestCase {
    // MARK: - Kind enum

    func testDefaultKindIsGeneral() {
        let error = AppError(message: "something broke")
        XCTAssertEqual(error.kind, .general)
    }

    func testUnsupportedURLKind() {
        let error = AppError(kind: .unsupportedURL, message: "bad url")
        XCTAssertEqual(error.kind, .unsupportedURL)
        XCTAssertNil(error.recoverySuggestion)
    }

    func testKindDoesNotAffectEquality() {
        let a = AppError(kind: .general, message: "msg")
        let b = AppError(kind: .unsupportedURL, message: "msg")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Codable backward compatibility

    func testDecodeWithoutKindDefaultsToGeneral() throws {
        let json = #"{"message":"oops","recoverySuggestion":"try again"}"#
        let decoded = try JSONDecoder().decode(AppError.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.kind, .general)
        XCTAssertEqual(decoded.message, "oops")
        XCTAssertEqual(decoded.recoverySuggestion, "try again")
    }

    func testRoundTripWithKind() throws {
        let original = AppError(kind: .unsupportedURL, message: "not supported")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppError.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testRoundTripGeneralKind() throws {
        let original = AppError(message: "generic", recoverySuggestion: "fix it")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppError.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
