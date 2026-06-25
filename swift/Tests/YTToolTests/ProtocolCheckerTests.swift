import XCTest
@testable import YTTool

final class ProtocolCheckerTests: XCTestCase {
    // P2: single allowed component
    func testAllowedHTTPS() {
        if case .allowed = ProtocolChecker.check(transportProtocol: "https") {} else {
            XCTFail("https should be allowed")
        }
    }

    func testAllowedHTTP() {
        if case .allowed = ProtocolChecker.check(transportProtocol: "http") {} else {
            XCTFail("http should be allowed")
        }
    }

    func testAllowedM3U8() {
        if case .allowed = ProtocolChecker.check(transportProtocol: "m3u8") {} else {
            XCTFail("m3u8 should be allowed")
        }
    }

    func testAllowedM3U8Native() {
        if case .allowed = ProtocolChecker.check(transportProtocol: "m3u8_native") {} else {
            XCTFail("m3u8_native should be allowed")
        }
    }

    // P3: compound allowed
    func testCompoundHTTPSPlusHTTPS() {
        if case .allowed = ProtocolChecker.check(transportProtocol: "https+https") {} else {
            XCTFail("https+https should be allowed")
        }
    }

    // P4: http_dash_segments rejected
    func testHTTPDashSegmentsRejected() {
        if case .rejected = ProtocolChecker.check(transportProtocol: "http_dash_segments") {} else {
            XCTFail("http_dash_segments should be rejected")
        }
    }

    // P5: rtmp rejected
    func testRTMPRejected() {
        if case .rejected = ProtocolChecker.check(transportProtocol: "rtmp") {} else {
            XCTFail("rtmp should be rejected")
        }
    }

    // P6: nil rejected
    func testNilRejected() {
        if case .rejected = ProtocolChecker.check(transportProtocol: nil) {} else {
            XCTFail("nil should be rejected")
        }
    }

    // P7: compound with disallowed component
    func testCompoundHTTPSPlusRTMPRejected() {
        if case .rejected = ProtocolChecker.check(transportProtocol: "https+rtmp") {} else {
            XCTFail("https+rtmp should be rejected")
        }
    }

    // P9: empty string rejected
    func testEmptyStringRejected() {
        if case .rejected = ProtocolChecker.check(transportProtocol: "") {} else {
            XCTFail("empty string should be rejected")
        }
    }

    // P10: only-plus rejected
    func testOnlyPlusRejected() {
        if case .rejected = ProtocolChecker.check(transportProtocol: "+") {} else {
            XCTFail("+ should be rejected")
        }
    }

    // P11: trailing plus → empty component
    func testTrailingPlusRejected() {
        if case .rejected = ProtocolChecker.check(transportProtocol: "https+") {} else {
            XCTFail("https+ should be rejected")
        }
    }

    // P12: leading plus → empty component
    func testLeadingPlusRejected() {
        if case .rejected = ProtocolChecker.check(transportProtocol: "+https") {} else {
            XCTFail("+https should be rejected")
        }
    }

    // P13: double plus → empty component
    func testDoublePlusRejected() {
        if case .rejected = ProtocolChecker.check(transportProtocol: "https++http") {} else {
            XCTFail("https++http should be rejected")
        }
    }

    // P14: non-canonical case rejected
    func testUppercaseRejected() {
        if case .rejected = ProtocolChecker.check(transportProtocol: "HTTPS") {} else {
            XCTFail("HTTPS should be rejected")
        }
    }

    // P15: trailing whitespace rejected
    func testTrailingWhitespaceRejected() {
        if case .rejected = ProtocolChecker.check(transportProtocol: "https ") {} else {
            XCTFail("trailing whitespace should be rejected")
        }
    }

    // P16: m3u8_native allowed
    func testM3U8NativeAllowed() {
        if case .allowed = ProtocolChecker.check(transportProtocol: "m3u8_native") {} else {
            XCTFail("m3u8_native should be allowed")
        }
    }
}
