import Foundation

enum Platform: String, Codable, Equatable {
    case youtube
    case bilibili

    static func detect(from url: String) -> Platform? {
        if isYouTubeSubscriptionURL(url) { return .youtube }
        if isBilibiliURL(url) { return .bilibili }
        return nil
    }
}

func isYouTubeSubscriptionURL(_ url: String) -> Bool {
    guard let components = URLComponents(string: url),
          let host = components.host?.lowercased() else { return false }
    return host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be"
}

func isBilibiliURL(_ url: String) -> Bool {
    guard let components = URLComponents(string: url),
          let host = components.host?.lowercased() else { return false }
    return host == "bilibili.com" || host.hasSuffix(".bilibili.com")
}

struct ChannelSubscription: Codable, Identifiable, Equatable {
    var id: UUID
    var channelID: String
    var channelName: String
    var channelURL: String
    var dateAdded: Date
    var isEnabled: Bool
    var lastCheckedDate: Date?
    var lastVideoID: String?
    var platform: Platform

    init(id: UUID, channelID: String, channelName: String, channelURL: String,
         dateAdded: Date, isEnabled: Bool, lastCheckedDate: Date? = nil,
         lastVideoID: String? = nil, platform: Platform = .youtube) {
        self.id = id
        self.channelID = channelID
        self.channelName = channelName
        self.channelURL = channelURL
        self.dateAdded = dateAdded
        self.isEnabled = isEnabled
        self.lastCheckedDate = lastCheckedDate
        self.lastVideoID = lastVideoID
        self.platform = platform
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        channelID = try container.decode(String.self, forKey: .channelID)
        channelName = try container.decode(String.self, forKey: .channelName)
        channelURL = try container.decode(String.self, forKey: .channelURL)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        lastCheckedDate = try container.decodeIfPresent(Date.self, forKey: .lastCheckedDate)
        lastVideoID = try container.decodeIfPresent(String.self, forKey: .lastVideoID)
        platform = try container.decodeIfPresent(Platform.self, forKey: .platform) ?? .youtube
    }
}

struct FeedVideo: Equatable, Codable {
    var videoID: String
    var title: String
    var channelName: String
    var publishedDate: Date?
    var url: String
    var thumbnailURL: String

    init(videoID: String, title: String, channelName: String,
         publishedDate: Date? = nil, url: String, thumbnailURL: String) {
        self.videoID = videoID
        self.title = title
        self.channelName = channelName
        self.publishedDate = publishedDate
        self.url = url
        self.thumbnailURL = thumbnailURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        videoID = try container.decode(String.self, forKey: .videoID)
        title = try container.decode(String.self, forKey: .title)
        channelName = try container.decode(String.self, forKey: .channelName)
        publishedDate = try container.decodeIfPresent(Date.self, forKey: .publishedDate)
        url = try container.decode(String.self, forKey: .url)
        thumbnailURL = try container.decodeIfPresent(String.self, forKey: .thumbnailURL)
            ?? "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg"
    }
}
