import XCTest
@testable import YTTool

final class ProcessRunnerTests: XCTestCase {
    func testConfigurationBuildsCommandLine() {
        let configuration = ProcessConfiguration(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["bash", "-lc", "echo test"]
        )

        XCTAssertEqual(
            configuration.commandLine,
            ["/usr/bin/env", "bash", "-lc", "echo test"]
        )
    }

    func testRunCapturesStdoutStderrAndExitCode() async throws {
        let runner = ProcessRunner()
        let result = try await runner.run(
            ProcessConfiguration(
                executableURL: fixtureURL,
                arguments: ["success"]
            )
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("fixture stdout"))
        XCTAssertTrue(result.stderr.contains("fixture stderr"))
    }

    func testRunReturnsNonZeroExitCode() async throws {
        let runner = ProcessRunner()
        let result = try await runner.run(
            ProcessConfiguration(
                executableURL: fixtureURL,
                arguments: ["fail"]
            )
        )

        XCTAssertEqual(result.exitCode, 17)
        XCTAssertTrue(result.stderr.contains("fixture failure"))
    }

    func testCancelTerminatesRunningProcess() async throws {
        let runner = ProcessRunner()
        let fixtureURL = fixtureURL
        let task = Task {
            try await runner.run(
                ProcessConfiguration(
                    executableURL: fixtureURL,
                    arguments: ["sleep", "5"],
                    terminationGracePeriod: .milliseconds(200)
                )
            )
        }

        try await Task.sleep(for: .milliseconds(200))
        try await runner.cancel(gracePeriod: .milliseconds(200))

        let result = try await task.value
        XCTAssertNotEqual(result.exitCode, 0)
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "YTTool/Resources/Binaries/probe-fixture", directoryHint: .notDirectory)
    }
}
