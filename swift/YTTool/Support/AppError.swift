import Foundation

struct AppError: Error, Codable, Equatable {
    enum Kind: String, Codable, Equatable {
        case general
        case unsupportedURL
    }

    var kind: Kind
    var message: String
    var recoverySuggestion: String?

    init(message: String, recoverySuggestion: String? = nil) {
        kind = .general
        self.message = message
        self.recoverySuggestion = recoverySuggestion
    }

    init(kind: Kind, message: String, recoverySuggestion: String? = nil) {
        self.kind = kind
        self.message = message
        self.recoverySuggestion = recoverySuggestion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .general
        message = try container.decode(String.self, forKey: .message)
        recoverySuggestion = try container.decodeIfPresent(String.self, forKey: .recoverySuggestion)
    }
}
