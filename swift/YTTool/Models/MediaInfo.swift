import Foundation

enum PlaylistMode: String, CaseIterable, Codable, Equatable, Identifiable {
    case onlyFirstItem
    case wholePlaylistBestVideo
    case wholePlaylistBestAudio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onlyFirstItem:
            return "Only first item"
        case .wholePlaylistBestVideo:
            return "Whole playlist: best video"
        case .wholePlaylistBestAudio:
            return "Whole playlist: best audio"
        }
    }

    var downloadsWholePlaylist: Bool {
        self != .onlyFirstItem
    }
}

enum PlaylistVideoQualityStrategy: String, CaseIterable, Codable, Equatable, Identifiable {
    case bestCompatibility
    case preferHigherQuality

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bestCompatibility:
            return "Best compatibility"
        case .preferHigherQuality:
            return "Prefer higher quality"
        }
    }
}

enum PlaylistAudioQualityStrategy: String, CaseIterable, Codable, Equatable, Identifiable {
    case moreCompatible
    case higherQuality

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moreCompatible:
            return "More compatible"
        case .higherQuality:
            return "Higher quality"
        }
    }
}

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

    var friendlyCodec: String { mapCodecName(codec) }
    var formattedBitrate: String { bitrateKbps.map { String(format: "%.0fk", $0) } ?? "—" }
    var formattedFileSize: String { formatFileSize(fileSizeBytes) }

    var displayLine: String {
        "\(id)  \(resolution)  \(friendlyCodec)  \(fps)fps  \(formattedBitrate)  \(formattedFileSize)  \(note)"
    }
}

struct AudioFormat: Codable, Equatable, Identifiable {
    var id: String
    var codec: String
    var bitrateKbps: Double?
    var fileSizeBytes: Int64?
    var note: String

    var friendlyCodec: String { mapCodecName(codec) }
    var formattedBitrate: String { bitrateKbps.map { String(format: "%.0fk", $0) } ?? "—" }
    var formattedFileSize: String { formatFileSize(fileSizeBytes) }

    var displayLine: String {
        "\(id)  \(friendlyCodec)  \(formattedBitrate)  \(formattedFileSize)  \(note)"
    }
}

// MARK: - Helpers

private func mapCodecName(_ raw: String) -> String {
    let lower = raw.lowercased()
    if lower.hasPrefix("avc1") || lower.hasPrefix("avc3") || lower == "h264" { return "H.264" }
    if lower.hasPrefix("av01") || lower == "av1"                              { return "AV1" }
    if lower == "vp9"  || lower.hasPrefix("vp09")                            { return "VP9" }
    if lower == "vp8"  || lower.hasPrefix("vp08")                            { return "VP8" }
    if lower.hasPrefix("hvc1") || lower.hasPrefix("hev1")
        || lower == "h265" || lower == "hevc"                                { return "HEVC" }
    if lower.hasPrefix("mp4a")                                               { return "AAC" }
    if lower == "opus"                                                       { return "Opus" }
    if lower == "mp3"                                                        { return "MP3" }
    if lower == "vorbis"                                                     { return "Vorbis" }
    if lower == "flac"                                                       { return "FLAC" }
    return raw
}

private func formatFileSize(_ bytes: Int64?) -> String {
    guard let bytes, bytes > 0 else { return "—" }
    let mb = Double(bytes) / 1_048_576
    if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
    if mb >= 1    { return String(format: "%.1f MB", mb) }
    return String(format: "%.0f KB", mb * 1024)
}
