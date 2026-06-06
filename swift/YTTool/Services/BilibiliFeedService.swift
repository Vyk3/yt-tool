import CryptoKit
@preconcurrency import Foundation

// MARK: - Anti-crawl resilience notes
//
// bilibili blocks URLSession via TLS fingerprinting; curl's fingerprint
// currently passes. If curl gets blocked too, known alternatives:
//   1. Cookie-based auth: extract SESSDATA/bili_jct from a browser login,
//      pass via `-b` / `--cookie` to curl. Most reliable but requires
//      user-provided credentials and periodic refresh.
//   2. User-Agent rotation: cycle through recent browser UA strings per
//      request. Helps against simple UA-based blocking, ineffective
//      against TLS fingerprinting.
//   3. curl_cffi / impersonate: a Python library that impersonates
//      specific browser TLS fingerprints. Would require shipping a
//      helper script or bridging via subprocess.
//   4. Proxy rotation: route requests through residential proxies to
//      avoid IP-based rate limiting.

actor BilibiliFeedService {
    private static let cardURL = "https://api.bilibili.com/x/web-interface/card"
    private static let viewURL = "https://api.bilibili.com/x/web-interface/view"
    private static let seasonsURL = "https://api.bilibili.com/x/polymer/web-space/seasons_series_list"
    private static let navURL = "https://api.bilibili.com/x/web-interface/nav"
    private static let arcSearchURL = "https://api.bilibili.com/x/space/wbi/arc/search"

    private static let maxRetries = 3
    private static let baseRetryDelay: TimeInterval = 1.0

    // MARK: - WBI signing

    static let mixinTable: [Int] = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
        27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
        37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
        22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
    ]

    private var cachedWBIKeys: (imgKey: String, subKey: String)?
    private var wbiKeysFetchedAt: Date?
    private static let wbiKeysTTL: TimeInterval = 3600

    private let log: @Sendable (ServiceLogKind, String) -> Void

    init(onLog: @escaping @Sendable (ServiceLogKind, String) -> Void = { _, _ in }) {
        self.log = onLog
    }

    // MARK: - HTTP (via curl)

    /// Fetch JSON data from a URL using `/usr/bin/curl` with retry.
    ///
    /// bilibili's anti-bot rejects requests from URLSession based on
    /// TLS fingerprinting. curl's TLS fingerprint passes their checks.
    /// Retries up to `maxRetries` times with exponential backoff on
    /// transport-level failures (curl exit != 0 or empty response).
    private nonisolated func curlFetch(url: String) async throws -> Data {
        var lastError: Error = FeedError.feedFetchFailed
        for attempt in 0..<Self.maxRetries {
            try Task.checkCancellation()
            if attempt > 0 {
                let delay = Self.baseRetryDelay * pow(2.0, Double(attempt - 1))
                log(.lifecycle, "Retry \(attempt)/\(Self.maxRetries - 1) after \(String(format: "%.0f", delay))s")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            do {
                return try await curlFetchOnce(url: url)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                log(.lifecycle, "curl failed (attempt \(attempt + 1)/\(Self.maxRetries)): \(url)")
            }
        }
        throw lastError
    }

    private nonisolated func curlFetchOnce(url: String) async throws -> Data {
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

    // MARK: - WBI key management

    private func getWBIKeys() async throws -> (imgKey: String, subKey: String) {
        if let cached = cachedWBIKeys,
           let fetchedAt = wbiKeysFetchedAt,
           Date().timeIntervalSince(fetchedAt) < Self.wbiKeysTTL
        {
            return cached
        }
        return try await refreshWBIKeys()
    }

    private func refreshWBIKeys() async throws -> (imgKey: String, subKey: String) {
        let data = try await curlFetch(url: Self.navURL)
        let response = try JSONDecoder().decode(BilibiliNavResponse.self, from: data)

        guard let imgURL = response.data?.wbiImg?.imgURL,
              let subURL = response.data?.wbiImg?.subURL
        else { throw FeedError.feedFetchFailed }

        let imgKey = Self.extractKeyFromURL(imgURL)
        let subKey = Self.extractKeyFromURL(subURL)
        guard !imgKey.isEmpty, !subKey.isEmpty else { throw FeedError.feedFetchFailed }

        cachedWBIKeys = (imgKey, subKey)
        wbiKeysFetchedAt = Date()
        return (imgKey, subKey)
    }

    private func invalidateWBIKeys() {
        cachedWBIKeys = nil
        wbiKeysFetchedAt = nil
    }

    private nonisolated static func extractKeyFromURL(_ urlString: String) -> String {
        guard let url = URL(string: urlString) else { return "" }
        return url.deletingPathExtension().lastPathComponent
    }

    nonisolated static func generateMixinKey(imgKey: String, subKey: String) -> String {
        let raw = Array(imgKey + subKey)
        guard raw.count >= mixinTable.count else {
            // WBI keys too short — return what we can; signParams will
            // produce a weak hash but callers already handle -403 retry.
            let mixed = mixinTable.compactMap { i -> Character? in
                i < raw.count ? raw[i] : nil
            }
            return String(mixed.prefix(32))
        }
        let mixed = mixinTable.map { raw[$0] }
        return String(mixed.prefix(32))
    }

    /// Sign parameters with WBI and return the complete percent-encoded query string.
    ///
    /// The returned string is ready to append after `?` — every value is
    /// cleaned, percent-encoded, and the `w_rid` digest matches the encoded form.
    nonisolated static func signParams(
        _ params: [String: String],
        mixinKey: String,
        timestamp: Int? = nil
    ) -> String {
        var params = params
        params["wts"] = String(timestamp ?? Int(Date().timeIntervalSince1970))

        let sorted = params.sorted { $0.key < $1.key }
        let encodedPairs = sorted.map { key, value in
            let cleaned = Self.wbiCleanValue(value)
            let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: .wbiAllowed) ?? cleaned
            return (key, encoded)
        }
        let query = encodedPairs.map { "\($0.0)=\($0.1)" }.joined(separator: "&")

        let digest = Insecure.MD5.hash(data: Data((query + mixinKey).utf8))
        let wRid = digest.map { String(format: "%02x", $0) }.joined()
        return "\(query)&w_rid=\(wRid)"
    }

    private nonisolated static func wbiCleanValue(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for c in value where c != "!" && c != "'" && c != "(" && c != ")" && c != "*" {
            result.append(c)
        }
        return result
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
    /// Primary: `wbi/arc/search` (returns all uploads, requires WBI signing).
    /// Fallback: `seasons_series_list` (only returns season/series videos).
    func fetchFeed(channelID: String) async throws -> [FeedVideo] {
        log(.lifecycle, "Fetching feed for mid=\(channelID)")
        do {
            let videos = try await fetchArcSearchFeed(channelID: channelID)
            log(.lifecycle, "arc/search returned \(videos.count) videos for mid=\(channelID)")
            return videos
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            log(.lifecycle, "arc/search failed for mid=\(channelID), falling back to seasons: \(error.localizedDescription)")
            let videos = try await fetchSeasonsFeed(channelID: channelID)
            log(.lifecycle, "seasons fallback returned \(videos.count) videos for mid=\(channelID)")
            return videos
        }
    }

    private func fetchArcSearchFeed(channelID: String, retryOnAuth: Bool = true) async throws -> [FeedVideo] {
        let keys = try await getWBIKeys()
        let keysTimestamp = wbiKeysFetchedAt
        let mixinKey = Self.generateMixinKey(imgKey: keys.imgKey, subKey: keys.subKey)

        let baseParams: [String: String] = [
            "mid": channelID,
            "ps": "15",
            "tid": "0",
            "pn": "1",
            "order": "pubdate",
        ]
        let query = Self.signParams(baseParams, mixinKey: mixinKey)
        let data = try await curlFetch(url: "\(Self.arcSearchURL)?\(query)")

        let response = try JSONDecoder().decode(BilibiliArcSearchResponse.self, from: data)

        if response.code != 0 {
            log(.stderr, "arc/search response code=\(response.code) message=\(response.message ?? "nil") for mid=\(channelID)")
        }

        if response.code == -403, retryOnAuth {
            log(.lifecycle, "WBI auth rejected (-403), refreshing keys")
            if wbiKeysFetchedAt == keysTimestamp {
                invalidateWBIKeys()
            }
            return try await fetchArcSearchFeed(channelID: channelID, retryOnAuth: false)
        }
        guard response.code == 0 else { throw FeedError.feedFetchFailed }

        return parseArcSearchResponse(response)
    }

    private func fetchSeasonsFeed(channelID: String) async throws -> [FeedVideo] {
        let data = try await curlFetch(
            url: "\(Self.seasonsURL)?mid=\(channelID)&page_num=1&page_size=20"
        )
        return try parseFeedResponse(data: data, channelID: channelID, logContext: "fetchSeasonsFeed")
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
        log(.lifecycle, "card API failed for mid=\(mid), falling back to seasons→view chain")

        // Fallback — seasons → view chain
        let seasonsData = try await curlFetch(
            url: "\(Self.seasonsURL)?mid=\(mid)&page_num=1&page_size=1"
        )
        let seasonsResponse = try JSONDecoder().decode(BilibiliSeasonsResponse.self, from: seasonsData)

        if seasonsResponse.code != 0 {
            log(.stderr, "seasons response code=\(seasonsResponse.code) for mid=\(mid)")
        }

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
        if response.code != 0 {
            log(.stderr, "card response code=\(response.code) for mid=\(mid)")
        }
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
        if response.code != 0 {
            log(.stderr, "view response code=\(response.code) for bvid=\(bvid)")
        }
        guard response.code == 0,
              let owner = response.data?.owner,
              !owner.name.isEmpty
        else { throw FeedError.channelIDResolutionFailed }

        return (channelID: String(owner.mid), channelName: owner.name)
    }

    // MARK: - Response parsing

    private nonisolated static func makeFeedVideo(
        bvid: String, title: String, channelName: String,
        timestamp: Int, pic: String?
    ) -> FeedVideo {
        FeedVideo(
            videoID: bvid,
            title: title,
            channelName: channelName,
            publishedDate: Date(timeIntervalSince1970: TimeInterval(timestamp)),
            url: "https://www.bilibili.com/video/\(bvid)",
            thumbnailURL: normalizePicURL(pic ?? "")
        )
    }

    func parseArcSearchResponse(_ response: BilibiliArcSearchResponse) -> [FeedVideo] {
        guard let vlist = response.data?.list?.vlist else { return [] }
        return vlist.prefix(15).map { item in
            Self.makeFeedVideo(
                bvid: item.bvid, title: item.title,
                channelName: item.author ?? "",
                timestamp: item.created, pic: item.pic
            )
        }
    }

    /// Parse the `seasons_series_list` response into `[FeedVideo]`.
    ///
    /// Collects all archive entries across seasons and series, then sorts
    /// by creation time (newest first) and returns the most recent 15.
    func parseFeedResponse(data: Data, channelID _: String, logContext: String = "") throws -> [FeedVideo] {
        let response = try JSONDecoder().decode(BilibiliSeasonsResponse.self, from: data)
        if response.code != 0 {
            log(.stderr, "seasons response code=\(response.code)\(logContext.isEmpty ? "" : " (\(logContext))")")
        }
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

        // Archives don't carry the uploader name. SubscriptionPollingManager
        // merges channelName from the stored subscription anyway.
        return top.map { archive in
            Self.makeFeedVideo(
                bvid: archive.bvid, title: archive.title,
                channelName: "",
                timestamp: archive.ctime, pic: archive.pic
            )
        }
    }
    private nonisolated static func normalizePicURL(_ pic: String) -> String {
        if pic.hasPrefix("//") {
            return "https:\(pic)"
        } else if pic.hasPrefix("http://") {
            return pic.replacingOccurrences(of: "http://", with: "https://")
        }
        return pic
    }
}

// MARK: - CharacterSet extension

private extension CharacterSet {
    static let wbiAllowed: CharacterSet = {
        var cs = CharacterSet.alphanumerics
        cs.insert(charactersIn: "-._~")
        return cs
    }()
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

private struct BilibiliNavResponse: Decodable {
    var code: Int
    var data: NavData?

    struct NavData: Decodable {
        var wbiImg: WBIImg?

        enum CodingKeys: String, CodingKey {
            case wbiImg = "wbi_img"
        }
    }

    struct WBIImg: Decodable {
        var imgURL: String?
        var subURL: String?

        enum CodingKeys: String, CodingKey {
            case imgURL = "img_url"
            case subURL = "sub_url"
        }
    }
}

struct BilibiliArcSearchResponse: Decodable {
    var code: Int
    var message: String?
    var data: ArcSearchData?

    struct ArcSearchData: Decodable {
        var list: VList?
    }

    struct VList: Decodable {
        var vlist: [VListItem]?
    }

    struct VListItem: Decodable {
        var bvid: String
        var title: String
        var created: Int
        var pic: String?
        var author: String?
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
