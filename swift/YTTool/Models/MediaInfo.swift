import Foundation

struct MediaInfo: Codable, Equatable {
    var title: String
    var duration: TimeInterval?
    var webpageURL: String
    var videoFormats: [VideoFormat]
    var audioFormats: [AudioFormat]
}

struct VideoFormat: Codable, Equatable, Identifiable {
    var id: String
    var resolution: String
    var codec: String
    var fps: Int
    var bitrateKbps: Double?
    var fileSizeBytes: Int64?
    var note: String

    var displayLine: String {
        let bitratePart = bitrateKbps.map { String(format: "%.0fkbps", $0) } ?? "?"
        return "\(id)  \(resolution)  \(codec)  \(fps)fps  \(bitratePart)  \(note)"
    }
}

struct AudioFormat: Codable, Equatable, Identifiable {
    var id: String
    var codec: String
    var bitrateKbps: Double?
    var fileSizeBytes: Int64?
    var note: String

    var displayLine: String {
        let bitratePart = bitrateKbps.map { String(format: "%.0fkbps", $0) } ?? "?"
        return "\(id)  \(codec)  \(bitratePart)  \(note)"
    }
}
