import Foundation

enum AppLogScope: String, CaseIterable, Sendable {
    case app = "APP"
    case probe = "PROBE"
    case download = "DOWNLOAD"
}

enum AppLogLevel: String, CaseIterable, Sendable {
    case info = "INFO"
    case success = "OK"
    case warning = "WARN"
    case error = "ERROR"
}

struct AppLogEntry: Identifiable, Equatable, Sendable {
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
