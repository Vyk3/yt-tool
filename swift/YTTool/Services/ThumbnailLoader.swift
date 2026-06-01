import AppKit
import Foundation

actor ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private let cache = NSCache<NSString, NSImage>()
    private let session: URLSession
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private static let maxConcurrent = 4
    private var activeCount = 0

    private init() {
        cache.totalCostLimit = 50 * 1024 * 1024
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 100 * 1024 * 1024)
        session = URLSession(configuration: config)
    }

    func load(url: String, targetSize: CGSize = CGSize(width: 320, height: 180)) async -> NSImage? {
        let key = url as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        if let existing = inFlight[url] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            await waitForSlot()
            defer { releaseSlot() }

            guard let requestURL = normalizedThumbnailRequestURL(from: url) else { return nil }
            guard let (data, response) = try? await session.data(from: requestURL) else { return nil }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ..< 300).contains(httpResponse.statusCode) else { return nil }
            guard let image = NSImage(data: data) else { return nil }

            let downscaled = downsample(image, to: targetSize)
            let cost = Int(targetSize.width * targetSize.height * 4)
            cache.setObject(downscaled, forKey: key, cost: cost)
            return downscaled
        }

        inFlight[url] = task
        let result = await task.value
        inFlight.removeValue(forKey: url)
        return result
    }

    private func waitForSlot() async {
        while activeCount >= Self.maxConcurrent {
            await Task.yield()
        }
        activeCount += 1
    }

    private func releaseSlot() {
        activeCount -= 1
    }

    private func downsample(_ image: NSImage, to targetSize: CGSize) -> NSImage {
        let scaledSize = NSSize(width: targetSize.width * 2, height: targetSize.height * 2)
        let existing = image.size
        guard existing.width > scaledSize.width || existing.height > scaledSize.height else {
            return image
        }

        let result = NSImage(size: scaledSize)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: scaledSize),
                   from: NSRect(origin: .zero, size: existing),
                   operation: .copy, fraction: 1.0)
        result.unlockFocus()
        return result
    }
}

func normalizedThumbnailRequestURL(from rawURL: String) -> URL? {
    let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let urlString = trimmed.hasPrefix("//") ? "https:\(trimmed)" : trimmed
    guard var components = URLComponents(string: urlString),
          let scheme = components.scheme?.lowercased(),
          scheme == "http" || scheme == "https"
    else {
        return nil
    }

    if scheme == "http" {
        components.scheme = "https"
    }
    return components.url
}

func youTubeVideoID(from url: String) -> String? {
    guard let components = URLComponents(string: url) else { return nil }
    guard let host = components.host?.lowercased() else { return nil }

    if host == "youtu.be" {
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? nil : path
    }

    guard host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }

    let segments = components.path.split(separator: "/")
    if segments.count == 2, segments[0] == "shorts" || segments[0] == "live" {
        let id = String(segments[1])
        return id.isEmpty ? nil : id
    }

    return components.queryItems?.first(where: { $0.name == "v" })?.value
}

func thumbnailURL(for url: String) -> String? {
    if let videoID = youTubeVideoID(from: url) {
        return "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg"
    }
    return nil
}

enum BilibiliVideoID: Equatable {
    case bvid(String)
    case aid(String)

    var queryItem: URLQueryItem {
        switch self {
        case let .bvid(value):
            URLQueryItem(name: "bvid", value: value)
        case let .aid(value):
            URLQueryItem(name: "aid", value: value)
        }
    }
}

func bilibiliVideoID(from url: String) -> BilibiliVideoID? {
    guard let components = URLComponents(string: url),
          let host = components.host?.lowercased(),
          host == "bilibili.com" || host.hasSuffix(".bilibili.com")
    else {
        return nil
    }

    let segments = components.path.split(separator: "/").map(String.init)
    guard let videoIndex = segments.firstIndex(of: "video"),
          segments.indices.contains(videoIndex + 1)
    else {
        return nil
    }

    let rawID = segments[videoIndex + 1]
    if rawID.hasPrefix("BV") {
        return .bvid(rawID)
    }
    if rawID.hasPrefix("av") {
        let aid = String(rawID.dropFirst(2))
        return aid.isEmpty ? nil : .aid(aid)
    }
    return nil
}

actor RemoteThumbnailResolver {
    static let shared = RemoteThumbnailResolver()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        session = URLSession(configuration: config)
    }

    func resolve(url: String) async -> String? {
        if let direct = thumbnailURL(for: url) {
            return direct
        }
        if let videoID = bilibiliVideoID(from: url) {
            return await bilibiliThumbnailURL(for: videoID)
        }
        return nil
    }

    private func bilibiliThumbnailURL(for videoID: BilibiliVideoID) async -> String? {
        var components = URLComponents(string: "https://api.bilibili.com/x/web-interface/view")
        components?.queryItems = [videoID.queryItem]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")

        guard let (data, response) = try? await session.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode),
              let payload = try? JSONDecoder().decode(BilibiliViewResponse.self, from: data),
              payload.code == 0,
              let pic = payload.data?.pic,
              !pic.isEmpty
        else {
            return nil
        }

        return pic
    }
}

private struct BilibiliViewResponse: Decodable {
    var code: Int
    var data: BilibiliViewData?
}

private struct BilibiliViewData: Decodable {
    var pic: String?
}
