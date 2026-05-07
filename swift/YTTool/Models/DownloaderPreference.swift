import Foundation

enum DownloaderPreference: String, CaseIterable, Identifiable {
    case native
    case aria2c

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .native: "Built-in"
        case .aria2c: "aria2c (faster)"
        }
    }
}
