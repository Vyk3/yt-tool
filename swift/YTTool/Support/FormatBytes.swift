import Foundation

func formatBytes(_ bytes: Int64) -> String {
    let gb = Double(bytes) / 1_073_741_824
    if gb >= 1 { return String(format: "%.1f GB", gb) }
    let mb = Double(bytes) / 1_048_576
    if mb >= 1 { return String(format: "%.1f MB", mb) }
    return String(format: "%.0f KB", mb * 1024)
}
