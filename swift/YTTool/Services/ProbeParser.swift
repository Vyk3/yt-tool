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
                audioFormats: payload.formats.compactMap(Self.makeAudioFormat).sorted(by: audioSort)
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
        guard raw.vcodec?.lowercased() != "none" else {
            return nil
        }

        let hasAudio = raw.acodec?.lowercased() != "none" && raw.acodec != nil
        let resolution = raw.height.map { "\($0)p" } ?? raw.formatNote ?? "unknown"

        return VideoFormat(
            id: raw.formatID,
            resolution: resolution,
            codec: raw.vcodec ?? "unknown",
            fps: raw.fps ?? 0,
            bitrateKbps: raw.tbr,
            fileSizeBytes: raw.filesizeApprox ?? raw.filesize,
            note: hasAudio ? "muxed" : "video only"
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
}

private struct RawProbePayload: Decodable {
    var title: String?
    var duration: TimeInterval?
    var webpageURL: String?
    var formats: [RawFormat]

    enum CodingKeys: String, CodingKey {
        case title
        case duration
        case webpageURL = "webpage_url"
        case formats
    }
}

private struct RawFormat: Decodable {
    var formatID: String
    var vcodec: String?
    var acodec: String?
    var height: Int?
    var fps: Int?
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
