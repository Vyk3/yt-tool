import Foundation

struct ChannelSubscription: Codable, Identifiable, Equatable {
    var id: UUID
    var channelID: String
    var channelName: String
    var channelURL: String
    var dateAdded: Date
    var isEnabled: Bool
    var lastCheckedDate: Date?
    var lastVideoID: String?
}

struct FeedVideo: Equatable, Codable {
    var videoID: String
    var title: String
    var channelName: String
    var publishedDate: Date?
    var url: String

    var thumbnailURL: String {
        "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg"
    }
}
