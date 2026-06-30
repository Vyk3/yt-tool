import Foundation
import UserNotifications

/// Polls YouTube RSS feeds on a timer and notifies when subscribed channels upload new videos.
@MainActor
final class SubscriptionPollingManager: ObservableObject {
    @Published private(set) var isPolling = false
    @Published private(set) var newVideos: [FeedVideo] = []

    private let store: ChannelSubscriptionStore
    private let defaults: UserDefaults
    private let youtubeFeedService = YouTubeFeedService()
    private let bilibiliFeedService: BilibiliFeedService
    private nonisolated(unsafe) var timer: Timer?
    private(set) var recoveryMessage: String?

    /// Default poll interval in seconds (30 minutes).
    static let defaultPollInterval: TimeInterval = 30 * 60

    static let pollIntervalKey = "subscriptionPollInterval"
    static let newVideosKey = "subscriptionNewVideos"
    private static let corruptNewVideosBackupPrefix = "subscriptionNewVideos.corruptBackup."

    var pollInterval: TimeInterval {
        didSet {
            guard pollInterval != oldValue else { return }
            defaults.set(pollInterval, forKey: Self.pollIntervalKey)
            guard isPolling else { return }
            stopPolling()
            startPolling()
        }
    }

    init(
        store: ChannelSubscriptionStore,
        pollInterval: TimeInterval? = nil,
        defaults: UserDefaults = .standard,
        onBilibiliLog: @escaping @Sendable (ServiceLogKind, String) -> Void = { _, _ in }
    ) {
        self.store = store
        self.defaults = defaults
        bilibiliFeedService = BilibiliFeedService(onLog: onBilibiliLog)
        let stored = defaults.double(forKey: Self.pollIntervalKey)
        self.pollInterval = pollInterval ?? (stored > 0 ? stored : Self.defaultPollInterval)
        var recoveredMessage: String?
        newVideos = Self.loadNewVideos(defaults: defaults) { message in
            recoveredMessage = message
        }
        recoveryMessage = recoveredMessage
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Polling control

    func startPolling() {
        guard !isPolling else { return }
        isPolling = true
        scheduleTimer()
        // Run an initial check immediately.
        Task { await checkAllSubscriptions() }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
        isPolling = false
    }

    /// Manually trigger a check for all enabled subscriptions.
    func checkNow() {
        Task { await checkAllSubscriptions() }
    }

    func dismissVideo(_ video: FeedVideo) {
        newVideos.removeAll { $0.videoID == video.videoID }
        saveNewVideos()
    }

    func clearAllNewVideos() {
        newVideos.removeAll()
        saveNewVideos()
    }

    func clearStoredData() {
        stopPolling()
        newVideos.removeAll()
        defaults.removeObject(forKey: Self.newVideosKey)
        defaults.removeObject(forKey: Self.pollIntervalKey)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.corruptNewVideosBackupPrefix) {
            defaults.removeObject(forKey: key)
        }
        pollInterval = Self.defaultPollInterval
        defaults.removeObject(forKey: Self.pollIntervalKey)
        recoveryMessage = nil
    }

    func reloadStoredData() {
        var recoveredMessage: String?
        newVideos = Self.loadNewVideos(defaults: defaults) { message in
            recoveredMessage = message
        }
        recoveryMessage = recoveredMessage
        let stored = defaults.double(forKey: Self.pollIntervalKey)
        pollInterval = stored > 0 ? stored : Self.defaultPollInterval
    }

    // MARK: - Persistence

    private static func loadNewVideos(defaults: UserDefaults, onRecovery: (String) -> Void) -> [FeedVideo] {
        guard let data = defaults.data(forKey: newVideosKey) else { return [] }
        do {
            return try JSONDecoder().decode([FeedVideo].self, from: data)
        } catch {
            let backupKey = "\(corruptNewVideosBackupPrefix)\(UUID().uuidString)"
            defaults.set(data, forKey: backupKey)
            defaults.removeObject(forKey: newVideosKey)
            onRecovery("Recovered corrupt subscription videos at \(backupKey)")
            return []
        }
    }

    private func saveNewVideos() {
        if let data = try? JSONEncoder().encode(newVideos) {
            defaults.set(data, forKey: Self.newVideosKey)
        }
    }

    // MARK: - Private

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkAllSubscriptions()
            }
        }
    }

    private func checkAllSubscriptions() async {
        let enabled = store.subscriptions.filter(\.isEnabled)
        guard !enabled.isEmpty else { return }

        let ytService = youtubeFeedService
        let biliService = bilibiliFeedService
        let results = await withTaskGroup(of: (ChannelSubscription, [FeedVideo]?).self) { group in
            for subscription in enabled {
                group.addTask {
                    let videos: [FeedVideo]? = switch subscription.platform {
                    case .youtube:
                        try? await ytService.fetchFeed(channelID: subscription.channelID)
                    case .bilibili:
                        try? await biliService.fetchFeed(channelID: subscription.channelID)
                    }
                    return (subscription, videos)
                }
            }
            var collected: [(ChannelSubscription, [FeedVideo])] = []
            for await (sub, videos) in group {
                if let videos {
                    collected.append((sub, videos))
                }
            }
            return collected
        }

        let checkTime = Date()
        store.performBatchUpdate {
            for (subscription, videos) in results {
                processNewVideos(videos, for: subscription, now: checkTime)
            }
        }
    }

    nonisolated static func filterFreshVideos(
        from videos: [FeedVideo],
        previousLastVideoID: String,
        lastCheckedDate: Date?,
        now: Date,
        existingNewVideoIDs: Set<String>
    ) -> [FeedVideo] {
        let maxLookback: TimeInterval = 7 * 24 * 3600

        var candidates: [FeedVideo] = []
        for video in videos {
            if video.videoID == previousLastVideoID { break }
            candidates.append(video)
        }

        let cutoff = max(
            lastCheckedDate ?? .distantPast,
            now.addingTimeInterval(-maxLookback)
        )
        candidates = candidates.filter { video in
            guard let pubDate = video.publishedDate else { return false }
            return pubDate > cutoff
        }

        var seen = existingNewVideoIDs
        return candidates.filter { seen.insert($0.videoID).inserted }
    }

    private func processNewVideos(_ videos: [FeedVideo], for subscription: ChannelSubscription, now: Date) {
        guard let latest = videos.first else {
            store.updateLastChecked(id: subscription.id, date: now, lastVideoID: subscription.lastVideoID)
            return
        }

        if !latest.channelName.isEmpty {
            store.updateChannelName(id: subscription.id, name: latest.channelName)
        }

        let previousLastVideoID = subscription.lastVideoID
        let previousLastCheckedDate = subscription.lastCheckedDate

        guard let previousLastVideoID else {
            store.updateLastChecked(id: subscription.id, date: now, lastVideoID: latest.videoID)
            return
        }
        guard latest.videoID != previousLastVideoID else {
            store.updateLastChecked(id: subscription.id, date: now, lastVideoID: previousLastVideoID)
            return
        }

        let existingIDs = Set(newVideos.map(\.videoID))
        var freshVideos = Self.filterFreshVideos(
            from: videos,
            previousLastVideoID: previousLastVideoID,
            lastCheckedDate: previousLastCheckedDate,
            now: now,
            existingNewVideoIDs: existingIDs
        )

        for i in freshVideos.indices where freshVideos[i].channelName.isEmpty {
            freshVideos[i].channelName = subscription.channelName
        }

        if freshVideos.isEmpty {
            store.updateLastChecked(id: subscription.id, date: now, lastVideoID: previousLastVideoID)
            return
        }

        store.updateLastChecked(id: subscription.id, date: now, lastVideoID: latest.videoID)
        newVideos.append(contentsOf: freshVideos)
        saveNewVideos()

        sendNotification(videos: freshVideos, channelName: subscription.channelName)
    }

    private func sendNotification(videos: [FeedVideo], channelName: String) {
        let content = UNMutableNotificationContent()
        if videos.count == 1, let video = videos.first {
            content.title = channelName
            content.body = video.title
        } else {
            content.title = channelName
            content.body = "\(videos.count) new videos"
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "subscription-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
