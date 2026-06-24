import XCTest
@testable import YTTool

final class ExtraOptionTests: XCTestCase {
    // MARK: - T1: Allowlist内每个参数通过

    func testAllAllowlistedOptionsAccepted() throws {
        let inputs: [(String, ExtraOptionName)] = [
            ("--proxy http://host:8080", .proxy),
            ("--force-ipv4", .forceIPv4),
            ("--force-ipv6", .forceIPv6),
            ("--retries 3", .retries),
            ("--limit-rate 5M", .limitRate),
            ("--fragment-retries infinite", .fragmentRetries),
            ("--sleep-interval 1.5", .sleepInterval),
            ("--max-sleep-interval 5", .maxSleepInterval),
            ("--merge-output-format mp4", .mergeOutputFormat),
            ("--download-sections *0:00:30-0:01:00", .downloadSections),
            ("--sub-format srt", .subFormat),
            ("--restrict-filenames", .restrictFilenames),
            ("--no-mtime", .noMtime),
            ("--no-overwrites", .noOverwrites),
            ("--no-part", .noPart),
            ("--ignore-errors", .ignoreErrors),
            ("--no-abort-on-error", .noAbortOnError),
            ("--buffer-size 16K", .bufferSize),
        ]
        for (input, expectedName) in inputs {
            let result = try parseExtraOptions(input)
            XCTAssertEqual(result.first?.name, expectedName, "Failed for: \(input)")
        }
    }

    // MARK: - T2: Allowlist外参数拒绝

    func testUnknownOptionRejected() {
        XCTAssertThrowsError(try parseExtraOptions("--cookies-from-browser chrome")) { error in
            guard case OptionParseError.unknownOption = error else {
                return XCTFail("Expected unknownOption, got \(error)")
            }
        }
        XCTAssertThrowsError(try parseExtraOptions("--extractor-args youtube:player_client=web"))
        XCTAssertThrowsError(try parseExtraOptions("--write-thumbnail"))
        XCTAssertThrowsError(try parseExtraOptions("--remux-video mp4"))
        XCTAssertThrowsError(try parseExtraOptions("--audio-format mp3"))
    }

    // MARK: - T3: 短选项拒绝

    func testShortOptionsRejected() {
        XCTAssertThrowsError(try parseExtraOptions("-f 137")) { error in
            guard case OptionParseError.shortOption = error else {
                return XCTFail("Expected shortOption, got \(error)")
            }
        }
        XCTAssertThrowsError(try parseExtraOptions("-x"))
        XCTAssertThrowsError(try parseExtraOptions("-S ext:mp4"))
    }

    // MARK: - T4: -- 分隔符拒绝

    func testDoubleDashSeparatorRejected() {
        XCTAssertThrowsError(try parseExtraOptions("--limit-rate 5M -- extra")) { error in
            guard case OptionParseError.doubleDashSeparator = error else {
                return XCTFail("Expected doubleDashSeparator, got \(error)")
            }
        }
    }

    // MARK: - T5: 前缀匹配不生效

    func testPrefixMatchRejected() {
        XCTAssertThrowsError(try parseExtraOptions("--prox http://host")) { error in
            guard case OptionParseError.unknownOption("--prox") = error else {
                return XCTFail("Expected unknownOption(--prox), got \(error)")
            }
        }
        XCTAssertThrowsError(try parseExtraOptions("--limit-rat 5M"))
    }

    // MARK: - T6: Value 校验

    func testMergeOutputFormatRejectsInvalidValues() {
        XCTAssertThrowsError(try parseExtraOptions("--merge-output-format avi")) { error in
            guard case OptionParseError.invalidValue(.mergeOutputFormat, "avi") = error else {
                return XCTFail("Expected invalidValue, got \(error)")
            }
        }
    }

    // MARK: - T7: 数值校验

    func testNumericValidationRejectsNegativeAndNaN() {
        XCTAssertThrowsError(try parseExtraOptions("--retries -1"))
        XCTAssertThrowsError(try parseExtraOptions("--sleep-interval NaN"))
        XCTAssertThrowsError(try parseExtraOptions("--sleep-interval -0.5"))
        XCTAssertThrowsError(try parseExtraOptions("--sleep-interval Infinity"))
    }

    func testRetriesAcceptsInfinite() throws {
        let opts = try parseExtraOptions("--retries infinite")
        XCTAssertEqual(opts.first?.value, "infinite")
    }

    // MARK: - T8: Flag 不接受 =value

    func testFlagRejectsEqualsValue() {
        XCTAssertThrowsError(try parseExtraOptions("--force-ipv4=true")) { error in
            guard case OptionParseError.flagWithValue = error else {
                return XCTFail("Expected flagWithValue, got \(error)")
            }
        }
    }

    // MARK: - T9: 不可重复 option 出现两次拒绝

    func testDuplicateNonRepeatableRejected() {
        XCTAssertThrowsError(try parseExtraOptions("--proxy http://a:80 --proxy http://b:80")) { error in
            guard case OptionParseError.duplicateOption(.proxy) = error else {
                return XCTFail("Expected duplicateOption, got \(error)")
            }
        }
    }

    func testDownloadSectionsAllowsRepeat() throws {
        let opts = try parseExtraOptions("--download-sections *0:00:00-0:00:30 --download-sections *0:01:00-0:02:00")
        XCTAssertEqual(opts.count, 2)
    }

    // MARK: - T10: --proxy socks5 拒绝

    func testProxySocksRejected() {
        XCTAssertThrowsError(try parseExtraOptions("--proxy socks5://host:1080"))
    }

    // MARK: - T11: --proxy userinfo 拒绝

    func testProxyUserinfoRejected() {
        XCTAssertThrowsError(try parseExtraOptions("--proxy http://user:pass@host:8080"))
    }

    // MARK: - T12: --proxy 空 host 拒绝

    func testProxyEmptyHostRejected() {
        XCTAssertThrowsError(try parseExtraOptions("--proxy http://"))
    }

    // MARK: - T13: Probe context 过滤

    func testDownloadOnlyOptionsFilteredFromProbe() throws {
        let opts = try parseExtraOptions("--proxy http://host:80 --limit-rate 5M --no-mtime")
        let probeArgs = renderExtraOptions(opts, for: .probe)
        XCTAssertTrue(probeArgs.contains("--proxy"))
        XCTAssertFalse(probeArgs.contains("--limit-rate"))
        XCTAssertFalse(probeArgs.contains("--no-mtime"))

        let downloadArgs = renderExtraOptions(opts, for: .download)
        XCTAssertTrue(downloadArgs.contains("--proxy"))
        XCTAssertTrue(downloadArgs.contains("--limit-rate"))
        XCTAssertTrue(downloadArgs.contains("--no-mtime"))
    }

    // MARK: - T14: Proxy probe+download 一致

    func testProxyConsistentAcrossContexts() throws {
        let opts = try parseExtraOptions("--proxy http://proxy.local:3128")
        let probeArgs = renderExtraOptions(opts, for: .probe)
        let downloadArgs = renderExtraOptions(opts, for: .download)

        let probeProxy = probeArgs.dropFirst().first { _ in true }
        let downloadProxy = downloadArgs.dropFirst().first { _ in true }
        XCTAssertEqual(probeProxy, "http://proxy.local:3128")
        XCTAssertEqual(downloadProxy, "http://proxy.local:3128")
    }

    // MARK: - T15: --force-ipv4 + --force-ipv6 互斥拒绝

    func testForceIPMutuallyExclusive() {
        XCTAssertThrowsError(try parseExtraOptions("--force-ipv4 --force-ipv6")) { error in
            guard case OptionParseError.mutuallyExclusive(.forceIPv4, .forceIPv6) = error else {
                return XCTFail("Expected mutuallyExclusive, got \(error)")
            }
        }
    }

    // MARK: - T16: --download-sections 分/秒 >= 60 拒绝

    func testDownloadSectionsInvalidMinuteSecond() {
        XCTAssertThrowsError(try parseExtraOptions("--download-sections *0:60:00-0:61:00"))
        XCTAssertThrowsError(try parseExtraOptions("--download-sections *0:00:60-0:01:00"))
    }

    // MARK: - T17: --download-sections 结束 <= 开始拒绝

    func testDownloadSectionsEndNotAfterStart() {
        XCTAssertThrowsError(try parseExtraOptions("--download-sections *0:01:00-0:00:30"))
        XCTAssertThrowsError(try parseExtraOptions("--download-sections *0:01:00-0:01:00"))
    }

    // MARK: - T18: 旧文案已替换 (verified in Localization.swift — not a runtime test)

    // MARK: - T19: --proxy credential redaction

    func testProxyRedaction() {
        let config = ProcessConfiguration(
            executableURL: URL(fileURLWithPath: "/usr/bin/yt-dlp"),
            arguments: ["--proxy", "http://user:pass@host:8080/path?q=1", "--retries", "3"]
        )
        let redacted = config.redactedCommandLine
        XCTAssertTrue(redacted.contains("http://host:8080"))
        XCTAssertFalse(redacted.joined(separator: " ").contains("user"))
        XCTAssertFalse(redacted.joined(separator: " ").contains("pass"))
        XCTAssertFalse(redacted.joined(separator: " ").contains("path"))
    }

    // MARK: - T20: Redaction --proxy=value

    func testProxyRedactionEqualsForm() {
        let config = ProcessConfiguration(
            executableURL: URL(fileURLWithPath: "/usr/bin/yt-dlp"),
            arguments: ["--proxy=http://secret@host:3128"]
        )
        let redacted = config.redactedCommandLine
        XCTAssertTrue(redacted.contains("--proxy=http://host:3128"))
        XCTAssertFalse(redacted.joined(separator: " ").contains("secret"))
    }

    // MARK: - T21: Value option --name=value 正向通过

    func testEqualsFormAccepted() throws {
        let opts = try parseExtraOptions("--limit-rate=5M --proxy=http://host:80")
        XCTAssertEqual(opts.count, 2)
        XCTAssertEqual(opts[0], ParsedExtraOption(name: .limitRate, value: "5M"))
        XCTAssertEqual(opts[1], ParsedExtraOption(name: .proxy, value: "http://host:80"))
    }

    // MARK: - T22: ExtraOptionName.allCases 与 help (contract test — separate file)

    // MARK: - Edge cases

    func testEmptyInputReturnsEmpty() throws {
        XCTAssertEqual(try parseExtraOptions(""), [])
        XCTAssertEqual(try parseExtraOptions("   "), [])
    }

    func testBarePositionalRejected() {
        XCTAssertThrowsError(try parseExtraOptions("https://example.com")) { error in
            guard case OptionParseError.barePositional = error else {
                return XCTFail("Expected barePositional, got \(error)")
            }
        }
    }

    func testRenderCanonicalForm() throws {
        let opts = try parseExtraOptions("--limit-rate=5M")
        let rendered = renderExtraOptions(opts, for: .download)
        XCTAssertEqual(rendered, ["--limit-rate", "5M"])
    }
}
