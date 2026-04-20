import Foundation

enum DownloadState: Equatable {
    case idle
    case preparing(commandPreview: String)
    case downloading(DownloadProgress)
    case succeeded(outputURL: URL)
    case failed(AppError)
    case cancelled
}

struct DownloadProgress: Equatable {
    var percentComplete: Double
    var summaryLine: String
}
