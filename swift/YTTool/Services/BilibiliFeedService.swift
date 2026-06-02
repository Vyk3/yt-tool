import CryptoKit
import Foundation

actor BilibiliFeedService {
    private var cachedMixinKey: String?
    private let session: URLSession

    private static let navURL = URL(string: "https://api.bilibili.com/x/web-interface/nav")!
    private static let arcSearchURL = URL(string: "https://api.bilibili.com/x/space/wbi/arc/search")!

    private static let mixinKeyEncTab: [Int] = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
        27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
        37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
        22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
    ]

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

    func resolveChannelID(
        from url: String,
        locator: BundledToolLocator = BundledToolLocator()
    ) async throws -> (channelID: String, channelName: String) {
        let ytDlp: URL
        do {
            ytDlp = try locator.locate(.ytDlp)
        } catch {
            throw FeedError.ytDlpNotFound
        }

        let process = Process()
        process.executableURL = ytDlp
        process.arguments = [
            "--print", "channel_id",
            "--print", "channel",
            "--playlist-items", "1",
            "--no-warnings",
            url,
        ]

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        let output: String = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                guard proc.terminationStatus == 0 else {
                    continuation.resume(throwing: FeedError.channelIDResolutionFailed)
                    return
                }
                let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: text)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: FeedError.channelIDResolutionFailed)
            }
        }

        let lines = output.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard lines.count >= 2, !lines[0].isEmpty else {
            throw FeedError.channelIDResolutionFailed
        }

        return (channelID: lines[0], channelName: lines[1])
    }

    func fetchFeed(channelID: String) async throws -> [FeedVideo] {
        let params: [String: String] = [
            "mid": channelID,
            "order": "pubdate",
            "pn": "1",
            "ps": "15",
        ]

        let signedParams = try await signParams(params)
        var components = URLComponents(url: Self.arcSearchURL, resolvingAgainstBaseURL: false)!
        components.queryItems = signedParams.sorted(by: { $0.key < $1.key })
            .map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let url = components.url else { throw FeedError.invalidFeedURL }

        var request = URLRequest(url: url)
        for (key, value) in Self.commonHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeedError.feedFetchFailed
        }

        if httpResponse.statusCode == 403 || httpResponse.statusCode == 412 {
            cachedMixinKey = nil
            throw FeedError.feedFetchFailed
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw FeedError.feedFetchFailed
        }

        return try parseFeedResponse(data: data)
    }

    // MARK: - WBI signing

    private func signParams(_ params: [String: String]) async throws -> [String: String] {
        let mixinKey = try await getMixinKey()
        var mutableParams = params
        mutableParams["wts"] = String(Int(Date().timeIntervalSince1970))

        let sorted = mutableParams.sorted(by: { $0.key < $1.key })
        let forbidden = CharacterSet(charactersIn: "!'()*")
        let queryString = sorted.map { pair in
            let cleanValue = pair.value.unicodeScalars
                .filter { !forbidden.contains($0) }
                .map(String.init)
                .joined()
            let encoded = cleanValue.addingPercentEncoding(withAllowedCharacters: .wbiAllowed) ?? cleanValue
            return "\(pair.key)=\(encoded)"
        }.joined(separator: "&")

        let toHash = queryString + mixinKey
        let digest = Insecure.MD5.hash(data: Data(toHash.utf8))
        let wRid = digest.map { String(format: "%02x", $0) }.joined()

        mutableParams["w_rid"] = wRid
        return mutableParams
    }

    private func getMixinKey() async throws -> String {
        if let cached = cachedMixinKey { return cached }

        var request = URLRequest(url: Self.navURL)
        for (key, value) in Self.commonHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, _) = try await session.data(for: request)
        let nav = try JSONDecoder().decode(BilibiliNavResponse.self, from: data)

        guard let imgURL = nav.data?.wbiImg?.imgURL,
              let subURL = nav.data?.wbiImg?.subURL
        else {
            throw FeedError.channelIDResolutionFailed
        }

        let imgKey = extractKey(from: imgURL)
        let subKey = extractKey(from: subURL)
        let rawKey = imgKey + subKey

        let mixinKey = String(Self.mixinKeyEncTab.prefix(32).map { i in
            let idx = rawKey.index(rawKey.startIndex, offsetBy: i)
            return rawKey[idx]
        })

        cachedMixinKey = mixinKey
        return mixinKey
    }

    private func extractKey(from urlString: String) -> String {
        let filename = URL(string: urlString)?.lastPathComponent ?? urlString
        return filename.replacingOccurrences(of: ".png", with: "")
    }

    // MARK: - Response parsing

    func parseFeedResponse(data: Data) throws -> [FeedVideo] {
        let response = try JSONDecoder().decode(BilibiliArcSearchResponse.self, from: data)
        guard response.code == 0 else { throw FeedError.feedFetchFailed }

        return (response.data?.list?.vlist ?? []).map { item in
            FeedVideo(
                videoID: item.bvid,
                title: item.title,
                channelName: item.author,
                publishedDate: Date(timeIntervalSince1970: TimeInterval(item.created)),
                url: "https://www.bilibili.com/video/\(item.bvid)",
                thumbnailURL: item.pic.hasPrefix("//")
                    ? "https:\(item.pic)"
                    : item.pic
            )
        }
    }
}

// MARK: - WBI percent-encoding

private extension CharacterSet {
    static let wbiAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}

// MARK: - API response models

private struct BilibiliNavResponse: Decodable {
    var data: NavData?

    struct NavData: Decodable {
        var wbiImg: WbiImg?

        enum CodingKeys: String, CodingKey {
            case wbiImg = "wbi_img"
        }
    }

    struct WbiImg: Decodable {
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
    var data: ArcData?

    struct ArcData: Decodable {
        var list: ArcList?
    }

    struct ArcList: Decodable {
        var vlist: [VideoItem]?
    }

    struct VideoItem: Decodable {
        var bvid: String
        var title: String
        var pic: String
        var created: Int
        var author: String
    }
}
