import Foundation

actor BilibiliFeedService {
    private let session: URLSession

    private static let cardURL = URL(string: "https://api.bilibili.com/x/web-interface/card")!
    private static let viewURL = URL(string: "https://api.bilibili.com/x/web-interface/view")!
    private static let seasonsURL = URL(string: "https://api.bilibili.com/x/polymer/web-space/seasons_series_list")!

    private static let commonHeaders: [String: String] = [
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Referer": "https://www.bilibili.com/",
    ]

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
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
            let name = try await fetchUploaderName(mid: mid)
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
        var components = URLComponents(url: Self.seasonsURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "mid", value: channelID),
            URLQueryItem(name: "page_num", value: "1"),
            URLQueryItem(name: "page_size", value: "20"),
        ]

        guard let url = components.url else { throw FeedError.invalidFeedURL }

        var request = URLRequest(url: url)
        for (key, value) in Self.commonHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedError.feedFetchFailed
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw FeedError.feedFetchFailed
        }

        return try parseFeedResponse(data: data, channelID: channelID)
    }

    // MARK: - Channel resolution helpers

    /// Fetch uploader name via the card API (no WBI required).
    private func fetchUploaderName(mid: String) async throws -> String {
        var components = URLComponents(url: Self.cardURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "mid", value: mid)]
        guard let url = components.url else { throw FeedError.channelIDResolutionFailed }

        var request = URLRequest(url: url)
        for (key, value) in Self.commonHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(BilibiliCardResponse.self, from: data)
        guard response.code == 0,
              let name = response.data?.card?.name,
              !name.isEmpty
        else { throw FeedError.channelIDResolutionFailed }

        return name
    }

    /// Resolve owner mid + name from a video's bvid via the view API.
    private func resolveFromVideoView(bvid: String) async throws -> (channelID: String, channelName: String) {
        var components = URLComponents(url: Self.viewURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "bvid", value: bvid)]
        guard let url = components.url else { throw FeedError.channelIDResolutionFailed }

        var request = URLRequest(url: url)
        for (key, value) in Self.commonHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, _) = try await session.data(for: request)
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
    func parseFeedResponse(data: Data, channelID: String) throws -> [FeedVideo] {
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
            let normalizedPic: String
            if pic.hasPrefix("//") {
                normalizedPic = "https:\(pic)"
            } else if pic.hasPrefix("http://") {
                normalizedPic = pic.replacingOccurrences(of: "http://", with: "https://")
            } else {
                normalizedPic = pic
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
