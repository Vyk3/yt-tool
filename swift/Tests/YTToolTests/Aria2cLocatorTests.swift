import XCTest
@testable import YTTool

final class Aria2cLocatorTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Aria2cLocatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testFindAria2cReturnsExecutableWellKnownPath() throws {
        let executable = tempDirectory.appendingPathComponent("aria2c")
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let found = Aria2cLocator().findAria2c(wellKnownPaths: [executable.path])

        XCTAssertEqual(found?.path, executable.path)
    }

    func testFindAria2cSkipsNonExecutableAndDoesNotFallBackToPath() throws {
        let nonExecutable = tempDirectory.appendingPathComponent("aria2c")
        try "".write(to: nonExecutable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: nonExecutable.path)

        let found = Aria2cLocator().findAria2c(wellKnownPaths: [nonExecutable.path])

        XCTAssertNil(found)
    }
}
