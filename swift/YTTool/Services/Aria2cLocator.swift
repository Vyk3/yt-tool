import Foundation

struct Aria2cLocator {
    private static let wellKnownPaths: [String] = [
        "/opt/homebrew/bin/aria2c",
        "/usr/local/bin/aria2c",
    ]

    func findAria2c(
        fileManager: FileManager = .default,
        wellKnownPaths: [String] = Self.wellKnownPaths
    ) -> URL? {
        for path in wellKnownPaths {
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}
