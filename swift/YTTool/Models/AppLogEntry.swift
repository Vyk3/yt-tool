import Foundation

enum AppLogScope: String, CaseIterable {
    case app = "APP"
    case probe = "PROBE"
    case download = "DOWNLOAD"
    case update = "UPDATE"
}

enum AppLogLevel: String, CaseIterable {
    case info = "INFO"
    case success = "OK"
    case warning = "WARN"
    case error = "ERROR"
}

struct AppLogEntry: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let scope: AppLogScope
    let level: AppLogLevel
    let message: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        scope: AppLogScope,
        level: AppLogLevel,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.scope = scope
        self.level = level
        self.message = message
    }
}
