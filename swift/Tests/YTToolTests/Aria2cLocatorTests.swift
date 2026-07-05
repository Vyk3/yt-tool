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

    // MARK: - Custom path

    func testCustomPathTakesPriorityOverWellKnownPaths() throws {
        let custom = tempDirectory.appendingPathComponent("custom-aria2c")
        try "#!/bin/sh\nexit 0\n".write(to: custom, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: custom.path)

        let wellKnown = tempDirectory.appendingPathComponent("aria2c")
        try "#!/bin/sh\nexit 0\n".write(to: wellKnown, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wellKnown.path)

        let found = Aria2cLocator().findAria2c(
            customPath: custom.path,
            wellKnownPaths: [wellKnown.path]
        )

        XCTAssertEqual(found?.path, custom.path)
    }

    func testInvalidCustomPathReturnsNilWithoutFallingBack() throws {
        let wellKnown = tempDirectory.appendingPathComponent("aria2c")
        try "#!/bin/sh\nexit 0\n".write(to: wellKnown, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wellKnown.path)

        let found = Aria2cLocator().findAria2c(
            customPath: "/nonexistent/aria2c",
            wellKnownPaths: [wellKnown.path]
        )

        XCTAssertNil(found, "Should not fall back to well-known paths when custom path is set but invalid")
    }

    func testEmptyCustomPathFallsBackToWellKnownPaths() throws {
        let wellKnown = tempDirectory.appendingPathComponent("aria2c")
        try "#!/bin/sh\nexit 0\n".write(to: wellKnown, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wellKnown.path)

        let found = Aria2cLocator().findAria2c(
            customPath: "",
            wellKnownPaths: [wellKnown.path]
        )

        XCTAssertEqual(found?.path, wellKnown.path)
    }

    func testNilCustomPathFallsBackToWellKnownPaths() throws {
        let wellKnown = tempDirectory.appendingPathComponent("aria2c")
        try "#!/bin/sh\nexit 0\n".write(to: wellKnown, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wellKnown.path)

        let found = Aria2cLocator().findAria2c(
            customPath: nil,
            wellKnownPaths: [wellKnown.path]
        )

        XCTAssertEqual(found?.path, wellKnown.path)
    }

    // MARK: - Path validation

    func testPathTraversalRejected() {
        XCTAssertFalse(Aria2cLocator.isValidCustomPath("/usr/../etc/passwd"))
    }

    func testNonExecutableCustomPathRejected() throws {
        let nonExec = tempDirectory.appendingPathComponent("aria2c")
        try "".write(to: nonExec, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: nonExec.path)

        XCTAssertFalse(Aria2cLocator.isValidCustomPath(nonExec.path))
    }

    func testNonExistentPathRejected() {
        XCTAssertFalse(Aria2cLocator.isValidCustomPath("/nonexistent/path/to/aria2c"))
    }

    func testEmptyPathRejected() {
        XCTAssertFalse(Aria2cLocator.isValidCustomPath(""))
    }

    func testDirectoryPathRejected() {
        XCTAssertFalse(Aria2cLocator.isValidCustomPath(tempDirectory.path))
    }

    func testValidExecutablePathAccepted() throws {
        let executable = tempDirectory.appendingPathComponent("aria2c")
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        XCTAssertTrue(Aria2cLocator.isValidCustomPath(executable.path))
    }

    func testTildeExpansionAccepted() throws {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let filename = ".aria2c-tilde-test-\(UUID().uuidString)"
        let executable = homeDir.appendingPathComponent(filename)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: executable)
        }
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let tildePath = "~/\(filename)"
        XCTAssertTrue(Aria2cLocator.isValidCustomPath(tildePath))
    }
}
