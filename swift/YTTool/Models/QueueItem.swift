import Foundation

enum QueueQualityStrategy: String, CaseIterable, Identifiable {
    case bestQuality
    case max1080p
    case max720p
    case audioOnly

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .bestQuality: "Best quality"
        case .max1080p: "1080p max"
        case .max720p: "720p max"
        case .audioOnly: "Audio only"
        }
    }

    var formatSelector: String {
        switch self {
        case .bestQuality: "bestvideo+bestaudio/best"
        case .max1080p: "bestvideo[height<=1080]+bestaudio/best[height<=1080]"
        case .max720p: "bestvideo[height<=720]+bestaudio/best[height<=720]"
        case .audioOnly: "bestaudio/best"
        }
    }
}

struct QueueItemConfig: Equatable {
    let outputDirectory: URL
    let cookiesFilePath: String?
    let extraArguments: [String]
    let audioTranscodeFormat: AudioTranscodeFormat
    let downloaderPreference: DownloaderPreference
    let qualityStrategy: QueueQualityStrategy
}

enum QueueItemStatus: Equatable {
    case pending
    case active
    case completed
    case failed
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: true
        case .pending, .active: false
        }
    }
}

@MainActor
final class QueueItem: ObservableObject, Identifiable {
    let id = UUID()
    let url: String
    let addedAt = Date()
    let config: QueueItemConfig

    @Published var status: QueueItemStatus = .pending
    @Published var downloadProgress: DownloadProgress?
    @Published var outputURL: URL?
    @Published var error: AppError?
    @Published var title: String?
    @Published var thumbnailURL: String?

    var runner: ProcessRunner?

    init(url: String, config: QueueItemConfig) {
        self.url = url
        self.config = config
    }
}
