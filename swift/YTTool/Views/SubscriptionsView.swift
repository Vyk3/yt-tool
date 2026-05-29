import SwiftUI

struct SubscriptionsView: View {
    @ObservedObject var store: ChannelSubscriptionStore
    @ObservedObject var pollingManager: SubscriptionPollingManager
    @State private var newChannelURL = ""
    @State private var isResolving = false
    @State private var resolveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            addChannelSection
            newVideosSection
            subscriptionListSection
        }
    }

    // MARK: - Add channel

    private var addChannelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Channel")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("YouTube channel or video URL", text: $newChannelURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addChannel() }
                    .disabled(isResolving)

                Button(action: addChannel) {
                    if isResolving {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Label("Subscribe", systemImage: "plus.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newChannelURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResolving)
            }

            if let resolveError {
                Text(resolveError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - New videos

    @ViewBuilder
    private var newVideosSection: some View {
        if !pollingManager.newVideos.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("New Videos")
                        .font(.headline)
                    Spacer()
                    Button("Clear All") {
                        pollingManager.clearAllNewVideos()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }

                ForEach(pollingManager.newVideos, id: \.videoID) { video in
                    NewVideoRow(video: video, onDismiss: {
                        pollingManager.dismissVideo(video)
                    })
                }
            }
        }
    }

    // MARK: - Subscription list

    private var subscriptionListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Channels (\(store.subscriptions.count))")
                    .font(.headline)
                Spacer()

                Button {
                    pollingManager.checkNow()
                } label: {
                    Label("Check Now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            if store.subscriptions.isEmpty {
                Text("No subscriptions yet. Add a channel above to get started.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(store.subscriptions) { sub in
                    SubscriptionRow(
                        subscription: sub,
                        onToggle: { store.toggleEnabled(id: sub.id) },
                        onRemove: { store.remove(id: sub.id) }
                    )
                }
            }
        }
    }

    // MARK: - Actions

    private func addChannel() {
        let url = newChannelURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        isResolving = true
        resolveError = nil

        Task {
            do {
                let service = YouTubeFeedService()
                let result = try await service.resolveChannelID(from: url)

                let subscription = ChannelSubscription(
                    id: UUID(),
                    channelID: result.channelID,
                    channelName: result.channelName,
                    channelURL: url,
                    dateAdded: Date(),
                    isEnabled: true,
                    lastCheckedDate: nil,
                    lastVideoID: nil
                )
                store.add(subscription)
                newChannelURL = ""
                resolveError = nil
            } catch {
                resolveError = error.localizedDescription
            }
            isResolving = false
        }
    }
}

// MARK: - Row views

private struct NewVideoRow: View {
    let video: FeedVideo
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(video.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(video.channelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let date = video.publishedDate {
                Text(date, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Link(destination: URL(string: video.url)!) {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SubscriptionRow: View {
    let subscription: ChannelSubscription
    let onToggle: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(
                get: { subscription.isEnabled },
                set: { _ in onToggle() }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(subscription.channelName)
                        .font(.callout.weight(.medium))
                    if let lastChecked = subscription.lastCheckedDate {
                        Text("Last checked: \(lastChecked, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not yet checked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.switch)

            Spacer()

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }
}
