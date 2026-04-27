import Foundation

struct AppError: Error, Codable, Equatable {
    var message: String
    var recoverySuggestion: String?
}
