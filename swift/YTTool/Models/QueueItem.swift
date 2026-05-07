import Foundation

struct QueueItemConfig: Equatable {
    let outputDirectory: URL
    let cookiesFilePath: String?
    let extraArguments: [String]
    let audioTranscodeFormat: AudioTranscodeFormat
    let downloaderPreference: DownloaderPreference
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

    var runner: ProcessRunner?

    init(url: String, config: QueueItemConfig) {
        self.url = url
        self.config = config
    }
}
