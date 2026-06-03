import Foundation

struct AppError: Error, Codable, Equatable {
    enum Kind: String, Codable, Equatable {
        case general
        case unsupportedURL
    }

    var kind: Kind
    var message: String
    var recoverySuggestion: String?

    init(kind: Kind = .general, message: String, recoverySuggestion: String? = nil) {
        self.kind = kind
        self.message = message
        self.recoverySuggestion = recoverySuggestion
    }
}
