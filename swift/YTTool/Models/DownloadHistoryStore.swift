import Foundation

@MainActor
final class DownloadHistoryStore: ObservableObject {
    private static let maxEntries = 50
    private static let fileName = "download_history.json"

    @Published private(set) var entries: [DownloadHistoryEntry] = []

    private let customStorageURL: URL?
    private(set) var recoveryMessage: String?

    var storageURL: URL? {
        if let customStorageURL { return customStorageURL }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("YTTool", isDirectory: true)
            .appendingPathComponent(Self.fileName)
    }

    init(storageURL: URL? = nil) {
        customStorageURL = storageURL
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

    func clearStoredData(fileManager: FileManager = .default) throws {
        entries = []
        guard let url = storageURL, fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func reload() {
        entries = []
        recoveryMessage = nil
        load()
    }

    /// File IO is synchronous on MainActor; runs once at startup with a small file, acceptable.
    private func load() {
        guard let url = storageURL,
              let data = try? Data(contentsOf: url)
        else { return }
        do {
            entries = try JSONDecoder().decode([DownloadHistoryEntry].self, from: data)
        } catch {
            backupCorruptFile(at: url)
            entries = []
        }
    }

    /// File IO is synchronous on MainActor; write frequency is low (once per completed
    /// download) so this is acceptable. Move to Task.detached if entries grow large.
    private func save() {
        guard let url = storageURL else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func backupCorruptFile(at url: URL, fileManager: FileManager = .default) {
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).corrupt-\(UUID().uuidString).bak")
        do {
            try fileManager.moveItem(at: url, to: backupURL)
            recoveryMessage = "Recovered corrupt download history at \(backupURL.lastPathComponent)"
        } catch {
            recoveryMessage = "Failed to back up corrupt download history: \(error.localizedDescription)"
        }
    }
}
