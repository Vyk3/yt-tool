import Foundation

struct PlaylistEntry: Identifiable, Equatable {
    let index: Int
    let title: String
    let duration: TimeInterval?
    let url: String

    var id: Int {
        index
    }

    var formattedDuration: String {
        guard let duration, duration > 0 else { return "—" }
        let total = Int(duration)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
