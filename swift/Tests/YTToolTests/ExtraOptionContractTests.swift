import XCTest
@testable import YTTool

final class ExtraOptionContractTests: XCTestCase {
    func testAllOptionsRecognizedByYtDlp() throws {
        let required = ProcessInfo.processInfo.environment["REQUIRE_YTDLP_OPTION_CONTRACT"] == "1"
        guard let helpFile = ProcessInfo.processInfo.environment["YT_DLP_HELP_FILE"] else {
            if required {
                XCTFail("REQUIRE_YTDLP_OPTION_CONTRACT=1 but YT_DLP_HELP_FILE not set")
            } else {
                throw XCTSkip("YT_DLP_HELP_FILE not set — skipping option contract test")
            }
            return
        }
        let helpContent = try String(contentsOfFile: helpFile, encoding: .utf8)
        let declaredOptions = Self.extractDeclaredOptions(from: helpContent)
        for option in ExtraOptionName.allCases {
            XCTAssertTrue(
                declaredOptions.contains(option.rawValue),
                "\(option.rawValue) not found as declared option in yt-dlp --help"
            )
        }
    }

    func testDeclarationParserFixtures() {
        let shortAlias = "  -4, --force-ipv4              Force connection to use IPv4"
        XCTAssertTrue(Self.extractDeclaredOptions(from: shortAlias).contains("--force-ipv4"))

        let descOnly = "  --verbose                     Print various --force-ipv4 debug info"
        XCTAssertTrue(Self.extractDeclaredOptions(from: descOnly).contains("--verbose"))
        XCTAssertFalse(Self.extractDeclaredOptions(from: descOnly).contains("--force-ipv4"))
    }

    private static func extractDeclaredOptions(from helpText: String) -> Set<String> {
        let longOptionRegex = try! NSRegularExpression(pattern: #"--[a-z][a-z0-9-]*"#)
        var result = Set<String>()
        for line in helpText.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("-") else { continue }
            let declaration: String = if let gap = trimmed.range(of: "  ",
                                                                 range: trimmed.index(trimmed.startIndex,
                                                                                      offsetBy: min(2, trimmed.count)) ..< trimmed.endIndex)
            {
                String(trimmed[..<gap.lowerBound])
            } else {
                trimmed
            }
            let nsRange = NSRange(declaration.startIndex..., in: declaration)
            for match in longOptionRegex.matches(in: declaration, range: nsRange) {
                if let range = Range(match.range, in: declaration) {
                    result.insert(String(declaration[range]))
                }
            }
        }
        return result
    }
}
