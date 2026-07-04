import Foundation

struct Aria2cLocator {
    private static let wellKnownPaths: [String] = [
        "/opt/homebrew/bin/aria2c",
        "/usr/local/bin/aria2c",
        "/opt/local/bin/aria2c",
    ]

    static func isValidCustomPath(_ path: String, fileManager: FileManager = .default) -> Bool {
        guard !path.isEmpty else { return false }
        let url = URL(fileURLWithPath: path)
        guard !url.pathComponents.contains("..") else { return false }
        return fileManager.isExecutableFile(atPath: path)
    }

    func findAria2c(
        customPath: String? = nil,
        fileManager: FileManager = .default,
        wellKnownPaths: [String] = Self.wellKnownPaths
    ) -> URL? {
        if let custom = customPath, !custom.isEmpty {
            if Self.isValidCustomPath(custom, fileManager: fileManager) {
                return URL(fileURLWithPath: custom)
            }
            return nil
        }

        for path in wellKnownPaths {
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}
