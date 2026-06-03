import Foundation

@MainActor
final class DownloadHistoryStore: ObservableObject {
    private static let maxEntries = 50
    private static let fileName = "download_history.json"

    @Published private(set) var entries: [DownloadHistoryEntry] = []

    private var fileURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("YTTool", isDirectory: true)
            .appendingPathComponent(Self.fileName)
    }

    init() {
        load()
    }

    func append(_ entry: DownloadHistoryEntry) {
        entries.append(entry)
        entries = Array(entries.suffix(Self.maxEntries))
        save()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    /// File IO is synchronous on MainActor; runs once at startup with a small file, acceptable.
    private func load() {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url)
        else { return }
        do {
            entries = try JSONDecoder().decode([DownloadHistoryEntry].self, from: data)
        } catch {
            // Decode failure (e.g. future schema change) — reset rather than crash.
            entries = []
        }
    }

    /// File IO is synchronous on MainActor; write frequency is low (once per completed
    /// download) so this is acceptable. Move to Task.detached if entries grow large.
    private func save() {
        guard let url = fileURL else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
