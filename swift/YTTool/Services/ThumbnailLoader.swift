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
        cache.totalCostLimit = 50 * 1_024 * 1_024
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 20 * 1_024 * 1_024, diskCapacity: 100 * 1_024 * 1_024)
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

            guard let requestURL = URL(string: url) else { return nil }
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

func youTubeVideoID(from url: String) -> String? {
    guard let components = URLComponents(string: url) else { return nil }
    guard let host = components.host?.lowercased() else { return nil }

    if host == "youtu.be" {
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? nil : path
    }

    guard host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }
    return components.queryItems?.first(where: { $0.name == "v" })?.value
}

func thumbnailURL(for url: String) -> String? {
    if let videoID = youTubeVideoID(from: url) {
        return "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg"
    }
    return nil
}
