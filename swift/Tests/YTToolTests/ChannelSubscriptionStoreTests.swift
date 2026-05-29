import XCTest
@testable import YTTool

@MainActor
final class ChannelSubscriptionStoreTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("YTToolTests-\(UUID().uuidString)")
            .appendingPathComponent("channel_subscriptions.json")
    }

    override func tearDown() async throws {
        // Clean up temp directory.
        let dir = tempURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: dir)
        try await super.tearDown()
    }

    private func makeStore() -> ChannelSubscriptionStore {
        ChannelSubscriptionStore(storageURL: tempURL)
    }

    private func makeSub(
        channelID: String = "UC_TEST",
        channelName: String = "Test Channel",
        isEnabled: Bool = true
    ) -> ChannelSubscription {
        ChannelSubscription(
            id: UUID(),
            channelID: channelID,
            channelName: channelName,
            channelURL: "https://www.youtube.com/channel/\(channelID)",
            dateAdded: Date(),
            isEnabled: isEnabled,
            lastCheckedDate: nil,
            lastVideoID: nil
        )
    }

    // MARK: - Add

    func testAddAppendsSubscription() {
        let store = makeStore()
        let sub = makeSub()

        store.add(sub)

        XCTAssertEqual(store.subscriptions.count, 1)
        XCTAssertEqual(store.subscriptions[0].channelID, "UC_TEST")
    }

    func testAddDeduplicatesByChannelID() {
        let store = makeStore()
        let sub1 = makeSub(channelID: "UC_DUP", channelName: "First")
        let sub2 = makeSub(channelID: "UC_DUP", channelName: "Second")

        store.add(sub1)
        store.add(sub2)

        XCTAssertEqual(store.subscriptions.count, 1)
        XCTAssertEqual(store.subscriptions[0].channelName, "First")
    }

    func testAddMultipleDistinctChannels() {
        let store = makeStore()
        store.add(makeSub(channelID: "UC_A"))
        store.add(makeSub(channelID: "UC_B"))
        store.add(makeSub(channelID: "UC_C"))

        XCTAssertEqual(store.subscriptions.count, 3)
    }

    // MARK: - Remove

    func testRemoveDeletesSubscription() {
        let store = makeStore()
        let sub = makeSub()
        store.add(sub)

        store.remove(id: sub.id)

        XCTAssertTrue(store.subscriptions.isEmpty)
    }

    func testRemoveNonexistentIDIsNoOp() {
        let store = makeStore()
        store.add(makeSub())

        store.remove(id: UUID())

        XCTAssertEqual(store.subscriptions.count, 1)
    }

    // MARK: - Toggle

    func testToggleEnabledFlipsState() {
        let store = makeStore()
        let sub = makeSub(isEnabled: true)
        store.add(sub)

        store.toggleEnabled(id: sub.id)
        XCTAssertFalse(store.subscriptions[0].isEnabled)

        store.toggleEnabled(id: sub.id)
        XCTAssertTrue(store.subscriptions[0].isEnabled)
    }

    // MARK: - Update

    func testUpdateLastCheckedSetsDateAndVideoID() {
        let store = makeStore()
        let sub = makeSub()
        store.add(sub)
        let now = Date()

        store.updateLastChecked(id: sub.id, date: now, lastVideoID: "vid_latest")

        XCTAssertEqual(store.subscriptions[0].lastCheckedDate, now)
        XCTAssertEqual(store.subscriptions[0].lastVideoID, "vid_latest")
    }

    func testUpdateLastCheckedPreservesVideoIDWhenNil() {
        let store = makeStore()
        let sub = makeSub()
        store.add(sub)
        store.updateLastChecked(id: sub.id, date: Date(), lastVideoID: "original")

        store.updateLastChecked(id: sub.id, date: Date(), lastVideoID: nil)

        XCTAssertEqual(store.subscriptions[0].lastVideoID, "original")
    }

    func testUpdateChannelNameChangesName() {
        let store = makeStore()
        let sub = makeSub(channelName: "Old Name")
        store.add(sub)

        store.updateChannelName(id: sub.id, name: "New Name")

        XCTAssertEqual(store.subscriptions[0].channelName, "New Name")
    }

    func testUpdateChannelNameSkipsWhenSame() {
        let store = makeStore()
        let sub = makeSub(channelName: "Same")
        store.add(sub)

        // Should not trigger a save (no assertion on I/O, but verifies no crash).
        store.updateChannelName(id: sub.id, name: "Same")
        XCTAssertEqual(store.subscriptions[0].channelName, "Same")
    }

    // MARK: - Persistence round-trip

    func testPersistsAndReloadsFromDisk() {
        let sub = makeSub(channelID: "UC_PERSIST", channelName: "Persist Test")

        // Write.
        let store1 = makeStore()
        store1.add(sub)

        // Read back.
        let store2 = ChannelSubscriptionStore(storageURL: tempURL)

        XCTAssertEqual(store2.subscriptions.count, 1)
        XCTAssertEqual(store2.subscriptions[0].channelID, "UC_PERSIST")
        XCTAssertEqual(store2.subscriptions[0].channelName, "Persist Test")
        XCTAssertEqual(store2.subscriptions[0].id, sub.id)
    }

    func testEmptyFileLoadsCleanly() {
        // No file written — store should start empty without errors.
        let store = makeStore()
        XCTAssertTrue(store.subscriptions.isEmpty)
    }

    func testCorruptedFileLoadsEmpty() throws {
        // Write garbage to the storage file.
        let dir = tempURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: tempURL)

        let store = ChannelSubscriptionStore(storageURL: tempURL)
        XCTAssertTrue(store.subscriptions.isEmpty)
    }
}
