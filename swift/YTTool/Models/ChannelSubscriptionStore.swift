import Foundation

@MainActor
final class ChannelSubscriptionStore: ObservableObject {
    private static let fileName = "channel_subscriptions.json"

    @Published private(set) var subscriptions: [ChannelSubscription] = []

    private let customStorageURL: URL?

    private var fileURL: URL? {
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

    // MARK: - Public

    private var isBatching = false

    func add(_ subscription: ChannelSubscription) {
        guard !subscriptions.contains(where: { $0.channelID == subscription.channelID }) else { return }
        subscriptions.append(subscription)
        saveIfNeeded()
    }

    func remove(id: UUID) {
        subscriptions.removeAll { $0.id == id }
        saveIfNeeded()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        subscriptions.move(fromOffsets: source, toOffset: destination)
        saveIfNeeded()
    }

    func moveInMemory(fromOffsets source: IndexSet, toOffset destination: Int) {
        subscriptions.move(fromOffsets: source, toOffset: destination)
    }

    func toggleEnabled(id: UUID) {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        subscriptions[index].isEnabled.toggle()
        saveIfNeeded()
    }

    func updateLastChecked(id: UUID, date: Date, lastVideoID: String?) {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        subscriptions[index].lastCheckedDate = date
        if let lastVideoID {
            subscriptions[index].lastVideoID = lastVideoID
        }
        saveIfNeeded()
    }

    func updateChannelName(id: UUID, name: String) {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }),
              subscriptions[index].channelName != name
        else { return }
        subscriptions[index].channelName = name
        saveIfNeeded()
    }

    /// Performs multiple mutations with a single disk write at the end.
    func performBatchUpdate(_ block: () -> Void) {
        isBatching = true
        block()
        isBatching = false
        save()
    }

    private func saveIfNeeded() {
        guard !isBatching else { return }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url)
        else { return }
        do {
            subscriptions = try JSONDecoder().decode([ChannelSubscription].self, from: data)
        } catch {
            subscriptions = []
        }
    }

    func save() {
        guard let url = fileURL else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(subscriptions) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
