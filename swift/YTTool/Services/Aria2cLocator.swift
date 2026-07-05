import Foundation

struct Aria2cLocator {
    private static let wellKnownPaths: [String] = [
        "/opt/homebrew/bin/aria2c",
        "/usr/local/bin/aria2c",
        "/opt/local/bin/aria2c",
    ]

    static func isValidCustomPath(_ path: String, fileManager: FileManager = .default) -> Bool {
        guard !path.isEmpty else { return false }
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        guard !url.pathComponents.contains("..") else { return false }
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: expanded, isDirectory: &isDir), !isDir.boolValue else { return false }
        return fileManager.isExecutableFile(atPath: expanded)
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
