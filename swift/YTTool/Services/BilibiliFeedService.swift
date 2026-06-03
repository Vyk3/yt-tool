@preconcurrency import Foundation

actor BilibiliFeedService {
    private static let cardURL = "https://api.bilibili.com/x/web-interface/card"
    private static let viewURL = "https://api.bilibili.com/x/web-interface/view"
    private static let seasonsURL = "https://api.bilibili.com/x/polymer/web-space/seasons_series_list"

    init() {}

    // MARK: - HTTP (via curl)

    /// Fetch JSON data from a URL using `/usr/bin/curl`.
    ///
    /// bilibili's anti-bot rejects requests from URLSession based on
    /// TLS fingerprinting. curl's TLS fingerprint passes their checks.
    private nonisolated func curlFetch(url: String) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "-s", "--max-time", "15",
            "-H", "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "-H", "Referer: https://www.bilibili.com/",
            url,
        ]

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        let stdout = stdoutPipe.fileHandleForReading
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: FeedError.feedFetchFailed)
                return
            }
            // Read stdout on a detached thread BEFORE waiting for termination.
            // If we read inside terminationHandler the pipe buffer (~64 KB) can
            // fill up, blocking curl's write and preventing termination.
            DispatchQueue.global(qos: .utility).async {
                let data = stdout.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0, !data.isEmpty else {
                    continuation.resume(throwing: FeedError.feedFetchFailed)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }

    // MARK: - Public

    /// Resolve a bilibili URL to (mid, uploader name).
    ///
    /// - Space URL (`space.bilibili.com/{mid}`): extract mid from path,
    ///   fetch uploader name via card API.
    /// - Video URL (`bilibili.com/video/BV...`): call view API to get
    ///   owner mid + name.
    func resolveChannelID(from url: String) async throws -> (channelID: String, channelName: String) {
        guard let components = URLComponents(string: url),
              let host = components.host?.lowercased()
        else { throw FeedError.channelIDResolutionFailed }

        // space.bilibili.com/{mid}
        if host == "space.bilibili.com" || host.hasSuffix(".space.bilibili.com") {
            let pathSegments = components.path.split(separator: "/")
            guard let midStr = pathSegments.first, !midStr.isEmpty else {
                throw FeedError.channelIDResolutionFailed
            }
            let mid = String(midStr)
            let name = try await resolveUploaderName(mid: mid)
            return (channelID: mid, channelName: name)
        }

        // bilibili.com/video/BV...
        if host == "bilibili.com" || host.hasSuffix(".bilibili.com") {
            let pathSegments = components.path.split(separator: "/")
            if let videoIdx = pathSegments.firstIndex(of: "video"),
               videoIdx + 1 < pathSegments.endIndex
            {
                let bvid = String(pathSegments[videoIdx + 1])
                return try await resolveFromVideoView(bvid: bvid)
            }
        }

        throw FeedError.channelIDResolutionFailed
    }

    /// Fetch recent videos for a bilibili channel (mid).
    ///
    /// Uses the `seasons_series_list` API which returns videos organized
    /// into seasons/series, sorted by creation time. This endpoint does
    /// not require WBI signing or cookies.
    func fetchFeed(channelID: String) async throws -> [FeedVideo] {
        let data = try await curlFetch(
            url: "\(Self.seasonsURL)?mid=\(channelID)&page_num=1&page_size=20"
        )
        return try parseFeedResponse(data: data, channelID: channelID)
    }

    // MARK: - Channel resolution helpers

    /// Resolve uploader name for a given mid.
    ///
    /// Strategy:
    /// 1. Try `card` API (single call, fastest).
    /// 2. Fallback: fetch `seasons_series_list` → pick a bvid →
    ///    `view` API → owner name. The card endpoint is frequently
    ///    blocked by bilibili's anti-bot (-352) while seasons and
    ///    view endpoints remain available.
    private func resolveUploaderName(mid: String) async throws -> String {
        // Fast path — card API
        if let name = try? await fetchUploaderName(mid: mid) {
            return name
        }

        // Fallback — seasons → view chain
        let seasonsData = try await curlFetch(
            url: "\(Self.seasonsURL)?mid=\(mid)&page_num=1&page_size=1"
        )
        let seasonsResponse = try JSONDecoder().decode(BilibiliSeasonsResponse.self, from: seasonsData)

        let bvid = seasonsResponse.data?.itemsLists?.seasonsList?.first?.archives?.first?.bvid
            ?? seasonsResponse.data?.itemsLists?.seriesList?.first?.archives?.first?.bvid

        if let bvid {
            let (_, name) = try await resolveFromVideoView(bvid: bvid)
            if !name.isEmpty { return name }
        }

        throw FeedError.channelIDResolutionFailed
    }

    /// Fetch uploader name via the card API (no WBI required).
    private func fetchUploaderName(mid: String) async throws -> String {
        let data = try await curlFetch(url: "\(Self.cardURL)?mid=\(mid)")
        let response = try JSONDecoder().decode(BilibiliCardResponse.self, from: data)
        guard response.code == 0,
              let name = response.data?.card?.name,
              !name.isEmpty
        else { throw FeedError.channelIDResolutionFailed }

        return name
    }

    /// Resolve owner mid + name from a video's bvid via the view API.
    private func resolveFromVideoView(bvid: String) async throws -> (channelID: String, channelName: String) {
        let data = try await curlFetch(url: "\(Self.viewURL)?bvid=\(bvid)")
        let response = try JSONDecoder().decode(BilibiliViewResponse.self, from: data)
        guard response.code == 0,
              let owner = response.data?.owner,
              !owner.name.isEmpty
        else { throw FeedError.channelIDResolutionFailed }

        return (channelID: String(owner.mid), channelName: owner.name)
    }

    // MARK: - Response parsing

    /// Parse the `seasons_series_list` response into `[FeedVideo]`.
    ///
    /// Collects all archive entries across seasons and series, then sorts
    /// by creation time (newest first) and returns the most recent 15.
    func parseFeedResponse(data: Data, channelID _: String) throws -> [FeedVideo] {
        let response = try JSONDecoder().decode(BilibiliSeasonsResponse.self, from: data)
        guard response.code == 0 else { throw FeedError.feedFetchFailed }

        let itemsLists = response.data?.itemsLists
        var allArchives: [BilibiliSeasonsResponse.Archive] = []

        for season in itemsLists?.seasonsList ?? [] {
            allArchives.append(contentsOf: season.archives ?? [])
        }
        for series in itemsLists?.seriesList ?? [] {
            allArchives.append(contentsOf: series.archives ?? [])
        }

        // Sort by creation time descending, take top 15
        allArchives.sort { $0.ctime > $1.ctime }
        let top = allArchives.prefix(15)

        // We need the uploader name; archives don't carry it.
        // The channelName will be set by SubscriptionPollingManager from the
        // stored subscription, or resolved during channel add. For now use
        // the channelID as a placeholder — the polling manager's
        // processNewVideos merges channelName from the subscription anyway.
        return top.map { archive in
            let pic = archive.pic ?? ""
            let normalizedPic: String = if pic.hasPrefix("//") {
                "https:\(pic)"
            } else if pic.hasPrefix("http://") {
                pic.replacingOccurrences(of: "http://", with: "https://")
            } else {
                pic
            }

            return FeedVideo(
                videoID: archive.bvid,
                title: archive.title,
                channelName: "",
                publishedDate: Date(timeIntervalSince1970: TimeInterval(archive.ctime)),
                url: "https://www.bilibili.com/video/\(archive.bvid)",
                thumbnailURL: normalizedPic
            )
        }
    }
}

// MARK: - API response models

private struct BilibiliCardResponse: Decodable {
    var code: Int
    var data: CardData?

    struct CardData: Decodable {
        var card: Card?
    }

    struct Card: Decodable {
        var mid: String
        var name: String
    }
}

private struct BilibiliViewResponse: Decodable {
    var code: Int
    var data: ViewData?

    struct ViewData: Decodable {
        var owner: Owner?
    }

    struct Owner: Decodable {
        var mid: Int
        var name: String
    }
}

struct BilibiliSeasonsResponse: Decodable {
    var code: Int
    var data: SeasonsData?

    struct SeasonsData: Decodable {
        var itemsLists: ItemsLists?

        enum CodingKeys: String, CodingKey {
            case itemsLists = "items_lists"
        }
    }

    struct ItemsLists: Decodable {
        var seasonsList: [SeasonOrSeries]?
        var seriesList: [SeasonOrSeries]?

        enum CodingKeys: String, CodingKey {
            case seasonsList = "seasons_list"
            case seriesList = "series_list"
        }
    }

    struct SeasonOrSeries: Decodable {
        var archives: [Archive]?
    }

    struct Archive: Decodable {
        var bvid: String
        var title: String
        var pic: String?
        var ctime: Int
    }
}
