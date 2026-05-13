import Foundation

struct DownloadHistoryEntry: Codable, Identifiable {
    var id: UUID
    var url: String
    var title: String?
    var outputPath: String?
    var dateCompleted: Date
    var succeeded: Bool
    var estimatedSizeBytes: Int64?
}
