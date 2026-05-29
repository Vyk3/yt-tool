import Foundation
import UserNotifications

/// Polls YouTube RSS feeds on a timer and notifies when subscribed channels upload new videos.
@MainActor
final class SubscriptionPollingManager: ObservableObject {
    @Published private(set) var isPolling = false
    @Published private(set) var newVideos: [FeedVideo] = []

    private let store: ChannelSubscriptionStore
    private let feedService = YouTubeFeedService()
    private var timer: Timer?

    /// Default poll interval in seconds (30 minutes).
    static let defaultPollInterval: TimeInterval = 30 * 60

    var pollInterval: TimeInterval {
        didSet {
            guard pollInterval != oldValue, isPolling else { return }
            stopPolling()
            startPolling()
        }
    }

    init(store: ChannelSubscriptionStore, pollInterval: TimeInterval = SubscriptionPollingManager.defaultPollInterval) {
        self.store = store
        self.pollInterval = pollInterval
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
    }

    func clearAllNewVideos() {
        newVideos.removeAll()
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

        for subscription in enabled {
            do {
                let videos = try await feedService.fetchFeed(channelID: subscription.channelID)
                processNewVideos(videos, for: subscription)
            } catch {
                // Feed fetch failed for this channel — skip, will retry next cycle.
            }
        }
    }

    private func processNewVideos(_ videos: [FeedVideo], for subscription: ChannelSubscription) {
        guard let latest = videos.first else { return }

        // Update channel name if feed provides a fresher one.
        if !latest.channelName.isEmpty {
            store.updateChannelName(id: subscription.id, name: latest.channelName)
        }

        let now = Date()
        let previousLastVideoID = subscription.lastVideoID

        // Update bookmark to the newest video.
        store.updateLastChecked(id: subscription.id, date: now, lastVideoID: latest.videoID)

        // On first check (no previous bookmark), don't flood notifications.
        guard let previousLastVideoID else { return }
        guard latest.videoID != previousLastVideoID else { return }

        // Collect all new videos (those published after the previously-seen one).
        var freshVideos: [FeedVideo] = []
        for video in videos {
            if video.videoID == previousLastVideoID { break }
            // Avoid duplicates in the newVideos list.
            if !newVideos.contains(where: { $0.videoID == video.videoID }) {
                freshVideos.append(video)
            }
        }

        guard !freshVideos.isEmpty else { return }
        newVideos.append(contentsOf: freshVideos)

        // Send a single notification summarizing new uploads.
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
