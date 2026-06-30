import XCTest
@testable import YTTool

final class SubscriptionPollingManagerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14

    private func video(
        _ id: String,
        publishedDate: Date? = nil,
        daysAgo: Double? = nil
    ) -> FeedVideo {
        let date: Date? = if let daysAgo {
            now.addingTimeInterval(-daysAgo * 86400)
        } else {
            publishedDate
        }
        return FeedVideo(
            videoID: id, title: "Title \(id)", channelName: "",
            publishedDate: date, url: "https://example.com/\(id)",
            thumbnailURL: ""
        )
    }

    // MARK: - 1. Anchor found, all recent

    func testAnchorFound_allRecentVideos() {
        let lastChecked = now.addingTimeInterval(-1800) // 30 min ago
        let videos = [
            video("new1", daysAgo: 0),
            video("new2", daysAgo: 0),
            video("anchor"),
        ]
        let result = SubscriptionPollingManager.filterFreshVideos(
            from: videos, previousLastVideoID: "anchor",
            lastCheckedDate: lastChecked, now: now, existingNewVideoIDs: []
        )
        XCTAssertEqual(result.map(\.videoID), ["new1", "new2"])
    }

    // MARK: - 2. Anchor found, stale video before anchor

    func testAnchorFound_staleVideoBeforeAnchor_filtered() {
        let lastChecked = now.addingTimeInterval(-1800)
        let videos = [
            video("new1", daysAgo: 0),
            video("stale", daysAgo: 365),
            video("anchor"),
        ]
        let result = SubscriptionPollingManager.filterFreshVideos(
            from: videos, previousLastVideoID: "anchor",
            lastCheckedDate: lastChecked, now: now, existingNewVideoIDs: []
        )
        XCTAssertEqual(result.map(\.videoID), ["new1"])
    }

    // MARK: - 3. Anchor found, nil publishedDate excluded

    func testAnchorFound_nilPublishedDate_excluded() {
        let lastChecked = now.addingTimeInterval(-1800)
        let videos = [
            video("new1", daysAgo: 0),
            video("nildate", publishedDate: nil),
            video("anchor"),
        ]
        let result = SubscriptionPollingManager.filterFreshVideos(
            from: videos, previousLastVideoID: "anchor",
            lastCheckedDate: lastChecked, now: now, existingNewVideoIDs: []
        )
        XCTAssertEqual(result.map(\.videoID), ["new1"])
    }

    // MARK: - 4. Anchor missing, recent videos pass

    func testAnchorMissing_recentVideosIncluded() {
        let lastChecked = now.addingTimeInterval(-1800)
        let videos = [
            video("a", daysAgo: 0),
            video("b", daysAgo: 0.01),
        ]
        let result = SubscriptionPollingManager.filterFreshVideos(
            from: videos, previousLastVideoID: "gone",
            lastCheckedDate: lastChecked, now: now, existingNewVideoIDs: []
        )
        XCTAssertEqual(result.map(\.videoID), ["a", "b"])
    }

    // MARK: - 5. Anchor missing, old videos filtered

    func testAnchorMissing_oldVideosFiltered() {
        let lastChecked = now.addingTimeInterval(-1800)
        let videos = [
            video("recent", daysAgo: 0),
            video("old1", daysAgo: 365),
            video("old2", daysAgo: 730),
        ]
        let result = SubscriptionPollingManager.filterFreshVideos(
            from: videos, previousLastVideoID: "gone",
            lastCheckedDate: lastChecked, now: now, existingNewVideoIDs: []
        )
        XCTAssertEqual(result.map(\.videoID), ["recent"])
    }

    // MARK: - 6. Anchor missing, nil publishedDate excluded

    func testAnchorMissing_nilPublishedDate_excluded() {
        let lastChecked = now.addingTimeInterval(-1800)
        let videos = [
            video("recent", daysAgo: 0),
            video("nodate", publishedDate: nil),
        ]
        let result = SubscriptionPollingManager.filterFreshVideos(
            from: videos, previousLastVideoID: "gone",
            lastCheckedDate: lastChecked, now: now, existingNewVideoIDs: []
        )
        XCTAssertEqual(result.map(\.videoID), ["recent"])
    }

    // MARK: - 7. Anchor missing, lastCheckedDate nil → 7-day window

    func testAnchorMissing_nilLastCheckedDate_uses7DayWindow() {
        let videos = [
            video("recent", daysAgo: 1),
            video("old", daysAgo: 10),
        ]
        let result = SubscriptionPollingManager.filterFreshVideos(
            from: videos, previousLastVideoID: "gone",
            lastCheckedDate: nil, now: now, existingNewVideoIDs: []
        )
        XCTAssertEqual(result.map(\.videoID), ["recent"])
    }

    // MARK: - 8. Max lookback cap

    func testMaxLookbackCap_oldLastCheckedDate_clampedTo7Days() {
        let lastChecked = now.addingTimeInterval(-30 * 86400) // 30 days ago
        let videos = [
            video("recent", daysAgo: 1),
            video("within30d", daysAgo: 10),
        ]
        let result = SubscriptionPollingManager.filterFreshVideos(
            from: videos, previousLastVideoID: "gone",
            lastCheckedDate: lastChecked, now: now, existingNewVideoIDs: []
        )
        XCTAssertEqual(result.map(\.videoID), ["recent"])
    }

    // MARK: - 9. Duplicates in existingNewVideoIDs

    func testExistingNewVideoIDs_notReadded() {
        let lastChecked = now.addingTimeInterval(-1800)
        let videos = [
            video("new1", daysAgo: 0),
            video("existing", daysAgo: 0),
            video("anchor"),
        ]
        let result = SubscriptionPollingManager.filterFreshVideos(
            from: videos, previousLastVideoID: "anchor",
            lastCheckedDate: lastChecked, now: now,
            existingNewVideoIDs: ["existing"]
        )
        XCTAssertEqual(result.map(\.videoID), ["new1"])
    }

    // MARK: - 10. Batch-internal duplicates

    func testBatchInternalDuplicates_keptOnce() {
        let lastChecked = now.addingTimeInterval(-1800)
        let videos = [
            video("dup", daysAgo: 0),
            video("dup", daysAgo: 0),
            video("unique", daysAgo: 0),
            video("anchor"),
        ]
        let result = SubscriptionPollingManager.filterFreshVideos(
            from: videos, previousLastVideoID: "anchor",
            lastCheckedDate: lastChecked, now: now, existingNewVideoIDs: []
        )
        XCTAssertEqual(result.map(\.videoID), ["dup", "unique"])
    }

    // MARK: - 11. Dismiss → reappear (clock-based)

    func testDismissedVideoDoesNotReappear() {
        // Video published 2 hours ago, seen at T1 (1 hour ago), dismissed.
        // Next poll: lastCheckedDate = T1, video's publishedDate < T1 → filtered.
        let publishedDate = now.addingTimeInterval(-7200)
        let lastChecked = now.addingTimeInterval(-3600) // T1
        let videos = [
            video("dismissed", publishedDate: publishedDate),
        ]
        let result = SubscriptionPollingManager.filterFreshVideos(
            from: videos, previousLastVideoID: "gone",
            lastCheckedDate: lastChecked, now: now, existingNewVideoIDs: []
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - 12. Empty video list

    func testEmptyVideoList() {
        let result = SubscriptionPollingManager.filterFreshVideos(
            from: [], previousLastVideoID: "any",
            lastCheckedDate: now, now: now, existingNewVideoIDs: []
        )
        XCTAssertTrue(result.isEmpty)
    }

    @MainActor
    func testLoadsPollIntervalFromInjectedDefaults() {
        let defaults = freshDefaults()
        defaults.set(TimeInterval(15 * 60), forKey: SubscriptionPollingManager.pollIntervalKey)
        let manager = SubscriptionPollingManager(store: makeStore(), defaults: defaults)

        XCTAssertEqual(manager.pollInterval, TimeInterval(15 * 60))
    }

    @MainActor
    func testCorruptNewVideosBackedUpAndCleared() {
        let defaults = freshDefaults()
        defaults.set(Data("not json".utf8), forKey: SubscriptionPollingManager.newVideosKey)

        let manager = SubscriptionPollingManager(store: makeStore(), defaults: defaults)

        XCTAssertTrue(manager.newVideos.isEmpty)
        XCTAssertNotNil(manager.recoveryMessage)
        XCTAssertNil(defaults.data(forKey: SubscriptionPollingManager.newVideosKey))
        XCTAssertTrue(defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix("subscriptionNewVideos.corruptBackup.") })
    }

    @MainActor
    func testClearStoredDataRemovesDefaultsAndResetsInterval() {
        let defaults = freshDefaults()
        defaults.set(TimeInterval(15 * 60), forKey: SubscriptionPollingManager.pollIntervalKey)
        defaults.set(Data("[]".utf8), forKey: SubscriptionPollingManager.newVideosKey)
        defaults.set(Data("bad".utf8), forKey: "subscriptionNewVideos.corruptBackup.test")
        let manager = SubscriptionPollingManager(store: makeStore(), defaults: defaults)

        manager.clearStoredData()

        XCTAssertEqual(manager.pollInterval, SubscriptionPollingManager.defaultPollInterval)
        XCTAssertTrue(manager.newVideos.isEmpty)
        XCTAssertNil(defaults.object(forKey: SubscriptionPollingManager.pollIntervalKey))
        XCTAssertNil(defaults.object(forKey: SubscriptionPollingManager.newVideosKey))
        XCTAssertFalse(defaults.dictionaryRepresentation().keys.contains { $0.hasPrefix("subscriptionNewVideos.corruptBackup.") })
    }

    @MainActor
    private func makeStore() -> ChannelSubscriptionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SubscriptionPollingManagerTests-\(UUID().uuidString)")
            .appendingPathComponent("channel_subscriptions.json")
        return ChannelSubscriptionStore(storageURL: url)
    }

    private func freshDefaults() -> UserDefaults {
        let suiteName = "SubscriptionPollingManagerTests.\(#function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
