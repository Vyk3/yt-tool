import Foundation

enum UpdateState: Equatable {
    case idle
    case checking
    case available(current: String, latest: String)
    case upToDate(version: String)
    case downloading(progress: Double)
    case verifying
    case completed(newVersion: String)
    case failed(AppError)
}

enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable
    case nightly

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .stable: "Stable"
        case .nightly: "Nightly"
        }
    }

    var apiURL: URL {
        switch self {
        case .stable:
            URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!
        case .nightly:
            URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp-nightly-builds/releases/latest")!
        }
    }
}
