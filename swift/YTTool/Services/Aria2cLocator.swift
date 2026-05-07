import Foundation

struct Aria2cLocator {
    private static let wellKnownPaths: [String] = [
        "/opt/homebrew/bin/aria2c",
        "/usr/local/bin/aria2c",
    ]

    func findAria2c(fileManager: FileManager = .default) -> URL? {
        for path in Self.wellKnownPaths {
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return whichAria2c()
    }

    private func whichAria2c() -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["aria2c"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}
