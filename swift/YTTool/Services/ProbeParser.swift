import Foundation

struct ProbeParser {
    func parse(_ data: Data) throws -> MediaInfo {
        let decoder = JSONDecoder()

        do {
            let payload = try decoder.decode(RawProbePayload.self, from: data)
            return MediaInfo(
                title: sanitizedTitle(payload.title),
                duration: payload.duration,
                webpageURL: payload.webpageURL ?? "",
                videoFormats: payload.formats.compactMap(Self.makeVideoFormat).sorted(by: videoSort),
                audioFormats: payload.formats.compactMap(Self.makeAudioFormat).sorted(by: audioSort),
                subtitleTracks: Self.makeSubtitleTracks(from: payload.subtitles, isAuto: false),
                autoSubtitleTracks: Self.makeSubtitleTracks(from: payload.automaticCaptions, isAuto: true)
            )
        } catch {
            throw AppError(
                message: "Failed to decode probe output.",
                recoverySuggestion: "Check whether yt-dlp returned valid single-video JSON."
            )
        }
    }

    private func sanitizedTitle(_ title: String?) -> String {
        let raw = title?.replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return raw?.isEmpty == false ? raw! : "unknown"
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

    private static func makeVideoFormat(from raw: RawFormat) -> VideoFormat? {
        // Exclude formats with no video track (explicit "none") or missing vcodec.
        guard let vcodec = raw.vcodec, vcodec.lowercased() != "none" else {
            return nil
        }

        let hasAudio = raw.acodec?.lowercased() != "none" && raw.acodec != nil
        let resolution = raw.height.map { "\($0)p" } ?? raw.formatNote ?? "unknown"

        return VideoFormat(
            id: raw.formatID,
            resolution: resolution,
            codec: vcodec,
            fps: Int((raw.fps ?? 0).rounded()),
            bitrateKbps: raw.tbr,
            fileSizeBytes: raw.filesizeApprox ?? raw.filesize,
            note: hasAudio ? "w/ audio" : "no audio"
        )
    }

    private static func makeAudioFormat(from raw: RawFormat) -> AudioFormat? {
        guard raw.vcodec?.lowercased() == "none", let acodec = raw.acodec, acodec.lowercased() != "none" else {
            return nil
        }

        return AudioFormat(
            id: raw.formatID,
            codec: acodec,
            bitrateKbps: raw.abr,
            fileSizeBytes: raw.filesizeApprox ?? raw.filesize,
            note: raw.formatNote ?? raw.ext ?? ""
        )
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
            .sorted { $0.lang < $1.lang }
    }
}

private struct RawSubtitleEntry: Decodable {
    var name: String?
}

private struct RawProbePayload: Decodable {
    var title: String?
    var duration: TimeInterval?
    var webpageURL: String?
    var formats: [RawFormat]
    var subtitles: [String: [RawSubtitleEntry]]?
    var automaticCaptions: [String: [RawSubtitleEntry]]?

    enum CodingKeys: String, CodingKey {
        case title
        case duration
        case webpageURL = "webpage_url"
        case formats
        case subtitles
        case automaticCaptions = "automatic_captions"
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
    }
}
