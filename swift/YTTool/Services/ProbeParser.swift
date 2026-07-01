import Foundation

struct ProbeParser {
    func parse(_ data: Data) throws -> MediaInfo {
        let decoder = JSONDecoder()

        do {
            let payload = try decoder.decode(RawProbePayload.self, from: data)
            let formats = payload.formats ?? []
            let dur = payload.duration
            return MediaInfo(
                title: sanitizedTitle(payload.title),
                duration: dur,
                webpageURL: payload.webpageURL ?? "",
                thumbnailURL: payload.thumbnail,
                viewCount: payload.viewCount,
                uploader: payload.channel ?? payload.uploader,
                uploadDate: Self.parseUploadDate(payload.uploadDate),
                videoFormats: formats.compactMap { Self.makeVideoFormat(from: $0, duration: dur) }.sorted(by: videoSort),
                audioFormats: formats.compactMap { Self.makeAudioFormat(from: $0, duration: dur) }.sorted(by: audioSort),
                subtitleTracks: Self.makeSubtitleTracks(from: payload.subtitles, isAuto: false),
                autoSubtitleTracks: Self.makeSubtitleTracks(from: payload.automaticCaptions, isAuto: true)
            )
        } catch let decodingError as DecodingError {
            throw AppError(
                message: "Failed to decode probe output.",
                recoverySuggestion: Self.decodingErrorDetail(decodingError)
            )
        } catch {
            throw AppError(
                message: "Failed to decode probe output.",
                recoverySuggestion: error.localizedDescription
            )
        }
    }

    private static func decodingErrorDetail(_ error: DecodingError) -> String {
        switch error {
        case let .keyNotFound(key, context):
            return "Missing key '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))."
        case let .typeMismatch(type, context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Type mismatch for \(type) at \(path): \(context.debugDescription)"
        case let .valueNotFound(type, context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Null value for \(type) at \(path)."
        case let .dataCorrupted(context):
            return "Corrupted data: \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    private func sanitizedTitle(_ title: String?) -> String {
        let raw = title?.replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return raw?.isEmpty == false ? raw! : "unknown"
    }

    /// Parse yt-dlp "YYYYMMDD" date string.
    private static func parseUploadDate(_ raw: String?) -> Date? {
        guard let raw, raw.count == 8 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: raw)
    }

    private func videoSort(lhs: VideoFormat, rhs: VideoFormat) -> Bool {
        if lhs.resolution != rhs.resolution {
            return lhs.resolution > rhs.resolution
        }
        return lhs.bitrateKbps ?? 0 > rhs.bitrateKbps ?? 0
    }

    private func audioSort(lhs: AudioFormat, rhs: AudioFormat) -> Bool {
        lhs.bitrateKbps ?? 0 > rhs.bitrateKbps ?? 0
    }

    private static func makeVideoFormat(from raw: RawFormat, duration: TimeInterval?) -> VideoFormat? {
        // Exclude formats with no video track (explicit "none") or missing vcodec.
        guard let vcodec = raw.vcodec, vcodec.lowercased() != "none" else {
            return nil
        }

        let hasAudio = raw.acodec?.lowercased() != "none" && raw.acodec != nil
        let resolution = raw.height.map { "\($0)p" } ?? raw.formatNote ?? "unknown"
        let fileSize = raw.filesizeApprox ?? raw.filesize ?? estimatedBytes(bitrateKbps: raw.tbr, duration: duration)

        return VideoFormat(
            id: raw.formatID,
            resolution: resolution,
            codec: vcodec,
            fps: Int((raw.fps ?? 0).rounded()),
            bitrateKbps: raw.tbr,
            fileSizeBytes: fileSize,
            note: hasAudio ? "w/ audio" : "no audio",
            transportProtocol: raw.protocol
        )
    }

    private static func makeAudioFormat(from raw: RawFormat, duration: TimeInterval?) -> AudioFormat? {
        guard raw.vcodec?.lowercased() == "none", let acodec = raw.acodec, acodec.lowercased() != "none" else {
            return nil
        }

        let fileSize = raw.filesizeApprox ?? raw.filesize ?? estimatedBytes(bitrateKbps: raw.abr, duration: duration)

        return AudioFormat(
            id: raw.formatID,
            codec: acodec,
            bitrateKbps: raw.abr,
            fileSizeBytes: fileSize,
            note: raw.formatNote ?? raw.ext ?? "",
            transportProtocol: raw.protocol
        )
    }

    /// Estimate file size from bitrate and duration when yt-dlp doesn't provide one.
    private static func estimatedBytes(bitrateKbps: Double?, duration: TimeInterval?) -> Int64? {
        guard let kbps = bitrateKbps, kbps > 0, let dur = duration, dur > 0 else { return nil }
        return Int64(kbps * 1000 / 8 * dur)
    }

    // MARK: - Playlist Parsing

    func parsePlaylist(_ data: Data) throws -> [PlaylistEntry] {
        let decoder = JSONDecoder()

        do {
            let payload = try decoder.decode(RawPlaylistPayload.self, from: data)
            let rawEntries = payload.entries ?? []
            return rawEntries.enumerated().compactMap { offset, raw in
                let index = offset + 1
                let title = raw.title ?? raw.id ?? "Item \(index)"
                let url =
                    if let directURL = raw.url, !directURL.isEmpty {
                        directURL
                    } else if let webURL = raw.webpageURL, !webURL.isEmpty {
                        webURL
                    } else if let id = raw.id, let ieKey = raw.ieKey, ieKey == "Youtube" {
                        "https://www.youtube.com/watch?v=\(id)"
                    } else {
                        ""
                    }
                return PlaylistEntry(index: index, title: title, duration: raw.duration, url: url)
            }
        } catch let decodingError as DecodingError {
            throw AppError(
                message: "Failed to decode playlist output.",
                recoverySuggestion: Self.decodingErrorDetail(decodingError)
            )
        } catch {
            throw AppError(
                message: "Failed to decode playlist output.",
                recoverySuggestion: error.localizedDescription
            )
        }
    }

    func parsePlaylistItemProbe(_ data: Data) throws -> MediaInfo {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return try parse(data)
        }
        if let type = json["_type"] as? String, type == "playlist",
           let entries = json["entries"] as? [[String: Any]],
           let first = entries.first
        {
            let entryData = try JSONSerialization.data(withJSONObject: first)
            return try parse(entryData)
        }
        return try parse(data)
    }

    private static func makeSubtitleTracks(
        from raw: [String: [RawSubtitleEntry]]?,
        isAuto: Bool
    ) -> [SubtitleTrack] {
        guard let raw else { return [] }
        return raw
            .filter { $0.key != "live_chat" }
            .map { lang, entries in
                SubtitleTrack(lang: lang, label: entries.first?.name ?? "", isAuto: isAuto)
            }
            .sorted { lhs, rhs in
                let nameOrder = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                if nameOrder != .orderedSame {
                    return nameOrder == .orderedAscending
                }
                return lhs.lang.localizedCaseInsensitiveCompare(rhs.lang) == .orderedAscending
            }
    }
}

private struct RawSubtitleEntry: Decodable {
    var name: String?
}

private struct RawProbePayload: Decodable {
    var title: String?
    var duration: TimeInterval?
    var webpageURL: String?
    var thumbnail: String?
    var viewCount: Int64?
    var uploader: String?
    var channel: String?
    var uploadDate: String?
    var formats: [RawFormat]?
    var subtitles: [String: [RawSubtitleEntry]]?
    var automaticCaptions: [String: [RawSubtitleEntry]]?

    enum CodingKeys: String, CodingKey {
        case title
        case duration
        case webpageURL = "webpage_url"
        case thumbnail
        case viewCount = "view_count"
        case uploader
        case channel
        case uploadDate = "upload_date"
        case formats
        case subtitles
        case automaticCaptions = "automatic_captions"
    }
}

private struct RawPlaylistPayload: Decodable {
    var entries: [RawPlaylistEntry]?

    enum CodingKeys: String, CodingKey {
        case entries
    }
}

private struct RawPlaylistEntry: Decodable {
    var id: String?
    var title: String?
    var duration: TimeInterval?
    var url: String?
    var ieKey: String?
    var webpageURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case duration
        case url
        case ieKey = "ie_key"
        case webpageURL = "webpage_url"
    }
}

private struct RawFormat: Decodable {
    var formatID: String
    var vcodec: String?
    var acodec: String?
    var height: Int?
    var fps: Double?
    var tbr: Double?
    var abr: Double?
    var ext: String?
    var formatNote: String?
    var filesize: Int64?
    var filesizeApprox: Int64?
    var `protocol`: String?

    enum CodingKeys: String, CodingKey {
        case formatID = "format_id"
        case vcodec
        case acodec
        case height
        case fps
        case tbr
        case abr
        case ext
        case formatNote = "format_note"
        case filesize
        case filesizeApprox = "filesize_approx"
        case `protocol`
    }
}
