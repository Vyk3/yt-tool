import Foundation

enum PlaylistMode: String, CaseIterable, Codable, Equatable, Identifiable {
    case onlyFirstItem
    case wholePlaylistBestVideo
    case wholePlaylistBestAudio

    var id: String {
        rawValue
    }

    func title(_ l: AppLanguage) -> String {
        switch (self, l) {
        case (.onlyFirstItem, .chinese): "仅第一个"
        case (.onlyFirstItem, .english): "Only first item"
        case (.wholePlaylistBestVideo, .chinese): "整个播放列表：最佳视频"
        case (.wholePlaylistBestVideo, .english): "Whole playlist: best video"
        case (.wholePlaylistBestAudio, .chinese): "整个播放列表：最佳音频"
        case (.wholePlaylistBestAudio, .english): "Whole playlist: best audio"
        }
    }

    var downloadsWholePlaylist: Bool {
        self != .onlyFirstItem
    }
}

enum PlaylistVideoQualityStrategy: String, CaseIterable, Codable, Equatable, Identifiable {
    case bestCompatibility
    case preferHigherQuality

    var id: String {
        rawValue
    }

    func title(_ l: AppLanguage) -> String {
        switch (self, l) {
        case (.bestCompatibility, .chinese): "最佳兼容性"
        case (.bestCompatibility, .english): "Best compatibility"
        case (.preferHigherQuality, .chinese): "偏好高画质"
        case (.preferHigherQuality, .english): "Prefer higher quality"
        }
    }
}

enum PlaylistAudioQualityStrategy: String, CaseIterable, Codable, Equatable, Identifiable {
    case moreCompatible
    case higherQuality

    var id: String {
        rawValue
    }

    func title(_ l: AppLanguage) -> String {
        switch (self, l) {
        case (.moreCompatible, .chinese): "更高兼容性"
        case (.moreCompatible, .english): "More compatible"
        case (.higherQuality, .chinese): "更高音质"
        case (.higherQuality, .english): "Higher quality"
        }
    }
}

enum PlaylistSubtitleMode: String, CaseIterable, Codable, Equatable, Identifiable {
    case none
    case manual
    case auto

    var id: String {
        rawValue
    }

    func title(_ l: AppLanguage) -> String {
        switch (self, l) {
        case (.none, .chinese): "无字幕"
        case (.none, .english): "No subtitles"
        case (.manual, .chinese): "手动字幕"
        case (.manual, .english): "Manual subtitles"
        case (.auto, .chinese): "自动字幕"
        case (.auto, .english): "Auto subtitles"
        }
    }
}

enum PlaylistSegmentMode: String, CaseIterable, Codable, Equatable, Identifiable {
    case fullItem
    case fixedRange

    var id: String {
        rawValue
    }

    func title(_ l: AppLanguage) -> String {
        switch (self, l) {
        case (.fullItem, .chinese): "完整项目"
        case (.fullItem, .english): "Full item"
        case (.fixedRange, .chinese): "固定时间范围"
        case (.fixedRange, .english): "Fixed time range"
        }
    }
}

enum PlaylistFormatMode: String, CaseIterable, Codable, Equatable, Identifiable {
    case unifiedStrategy
    case perItemMapping

    var id: String {
        rawValue
    }

    func title(_ l: AppLanguage) -> String {
        switch (self, l) {
        case (.unifiedStrategy, .chinese): "统一策略"
        case (.unifiedStrategy, .english): "Unified strategy"
        case (.perItemMapping, .chinese): "逐项选择格式"
        case (.perItemMapping, .english): "Per-item format selection"
        }
    }
}

struct MediaInfo: Codable, Equatable {
    var title: String
    var duration: TimeInterval?
    var webpageURL: String
    var thumbnailURL: String?
    var viewCount: Int64?
    var uploader: String?
    var uploadDate: Date?
    var videoFormats: [VideoFormat]
    var audioFormats: [AudioFormat]
    var subtitleTracks: [SubtitleTrack]
    var autoSubtitleTracks: [SubtitleTrack]
}

struct SubtitleTrack: Codable, Equatable, Identifiable {
    var lang: String
    var label: String
    var isAuto: Bool

    /// Namespaced so manual "en" and auto "en" don't collide in ForEach.
    var id: String {
        "\(isAuto ? "auto" : "manual").\(lang)"
    }

    var displayName: String {
        label.isEmpty ? lang : label
    }
}

struct VideoFormat: Codable, Equatable, Identifiable {
    var id: String
    var resolution: String
    var codec: String
    var fps: Int
    var bitrateKbps: Double?
    var fileSizeBytes: Int64?
    var note: String
    var transportProtocol: String? = nil

    var friendlyCodec: String {
        mapCodecName(codec)
    }

    var formattedBitrate: String {
        bitrateKbps.map { String(format: "%.0fk", $0) } ?? "—"
    }

    var formattedFileSize: String {
        formatFileSize(fileSizeBytes)
    }

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
    var transportProtocol: String? = nil

    var friendlyCodec: String {
        mapCodecName(codec)
    }

    var formattedBitrate: String {
        bitrateKbps.map { String(format: "%.0fk", $0) } ?? "—"
    }

    var formattedFileSize: String {
        formatFileSize(fileSizeBytes)
    }

    var displayLine: String {
        "\(id)  \(friendlyCodec)  \(formattedBitrate)  \(formattedFileSize)  \(note)"
    }
}

// MARK: - HLS Detection

func isHLSProtocol(_ proto: String?) -> Bool {
    guard let proto = proto?.lowercased() else { return false }
    return proto.split(separator: "+")
        .contains(where: { $0 == "m3u8" || $0 == "m3u8_native" })
}

func isDASHProtocol(_ proto: String?) -> Bool {
    guard let proto = proto?.lowercased() else { return false }
    return proto.contains("dash")
}

func classifyProtocol(_ proto: String?) -> String {
    if isHLSProtocol(proto) { return "HLS" }
    if isDASHProtocol(proto) { return "DASH" }
    guard let proto else { return "—" }
    let lower = proto.lowercased()
    if lower == "https" || lower == "http" { return "HTTP" }
    return proto.uppercased()
}

extension VideoFormat {
    var isHLS: Bool {
        isHLSProtocol(transportProtocol)
    }

    var protocolLabel: String {
        classifyProtocol(transportProtocol)
    }
}

extension AudioFormat {
    var isHLS: Bool {
        isHLSProtocol(transportProtocol)
    }

    var protocolLabel: String {
        classifyProtocol(transportProtocol)
    }
}

// MARK: - Format Filtering

/// Lower = higher priority. H.264/AAC > VP9/Opus > AV1.
func codecPriority(_ codec: String) -> Int {
    switch codec.lowercased() {
    case "h.264", "aac": 0
    case "vp9", "opus": 1
    case "av1": 2
    default: 3
    }
}

/// Keep one video format per resolution — prefer: H.264 > VP9 > AV1, higher bitrate.
/// When `excludeHLS` is true, filters out HLS (m3u8) formats first.
func filterVideoFormats(_ formats: [VideoFormat], excludeHLS: Bool = false) -> [VideoFormat] {
    let source = excludeHLS ? formats.filter { !$0.isHLS } : formats
    var bestByRes: [String: VideoFormat] = [:]
    var resOrder: [String] = []
    for fmt in source {
        if bestByRes[fmt.resolution] == nil {
            resOrder.append(fmt.resolution)
            bestByRes[fmt.resolution] = fmt
        } else {
            let existing = bestByRes[fmt.resolution]!
            if codecPriority(fmt.friendlyCodec) < codecPriority(existing.friendlyCodec) {
                bestByRes[fmt.resolution] = fmt
            } else if codecPriority(fmt.friendlyCodec) == codecPriority(existing.friendlyCodec),
                      (fmt.bitrateKbps ?? 0) > (existing.bitrateKbps ?? 0)
            {
                bestByRes[fmt.resolution] = fmt
            }
        }
    }
    return resOrder.compactMap { bestByRes[$0] }
}

/// Keep one audio format per quality tier — prefer: higher bitrate, AAC > Opus.
/// When `excludeHLS` is true, filters out HLS (m3u8) formats first.
func filterAudioFormats(_ formats: [AudioFormat], excludeHLS: Bool = false) -> [AudioFormat] {
    let source = excludeHLS ? formats.filter { !$0.isHLS } : formats
    var standard: AudioFormat?
    var basic: AudioFormat?
    for fmt in source {
        let bitrate = fmt.bitrateKbps ?? 0
        if bitrate >= 96 {
            if let existing = standard {
                if codecPriority(fmt.friendlyCodec) < codecPriority(existing.friendlyCodec) {
                    standard = fmt
                } else if codecPriority(fmt.friendlyCodec) == codecPriority(existing.friendlyCodec),
                          bitrate > (existing.bitrateKbps ?? 0)
                {
                    standard = fmt
                }
            } else {
                standard = fmt
            }
        } else {
            if basic == nil { basic = fmt }
        }
    }
    return [standard, basic].compactMap { $0 }
}

// MARK: - Helpers

private func mapCodecName(_ raw: String) -> String {
    let lower = raw.lowercased()
    if lower.hasPrefix("avc1") || lower.hasPrefix("avc3") || lower == "h264" { return "H.264" }
    if lower.hasPrefix("av01") || lower == "av1" { return "AV1" }
    if lower == "vp9" || lower.hasPrefix("vp09") { return "VP9" }
    if lower == "vp8" || lower.hasPrefix("vp08") { return "VP8" }
    if lower.hasPrefix("hvc1") || lower.hasPrefix("hev1")
        || lower == "h265" || lower == "hevc" { return "HEVC" }
    if lower.hasPrefix("mp4a") { return "AAC" }
    if lower == "opus" { return "Opus" }
    if lower == "mp3" { return "MP3" }
    if lower == "vorbis" { return "Vorbis" }
    if lower == "flac" { return "FLAC" }
    return raw
}

private func formatFileSize(_ bytes: Int64?) -> String {
    guard let bytes, bytes > 0 else { return "—" }
    let mb = Double(bytes) / 1_048_576
    if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
    if mb >= 1 { return String(format: "%.1f MB", mb) }
    return String(format: "%.0f KB", mb * 1024)
}
