import AppKit
import SwiftUI

struct SubscriptionsView: View {
    @ObservedObject var store: ChannelSubscriptionStore
    @ObservedObject var pollingManager: SubscriptionPollingManager
    var language: AppLanguage = .english
    var onAddToQueue: ((String) -> Void)? = nil
    @State private var newChannelURL = ""
    @State private var isResolving = false
    @State private var resolveError: String?
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showDeleteConfirmation = false

    /// Channel names that have unseen new videos.
    private var channelsWithNewVideos: Set<String> {
        Set(pollingManager.newVideos.map(\.channelName))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            addChannelSection
            newVideosSection
            channelListSection
        }
    }

    // MARK: - Add channel

    private var addChannelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField(Loc.channelURLPlaceholder(language), text: $newChannelURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addChannel() }
                    .disabled(isResolving)

                Button(action: addChannel) {
                    if isResolving {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    } else {
                        Label(Loc.subscribe(language), systemImage: "plus.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(
                    newChannelURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isResolving
                )
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
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(Loc.newVideos(language))
                        .font(.subheadline.weight(.semibold))
                    Spacer()

                    Button {
                        let urls = pollingManager.newVideos.map(\.url).joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(urls, forType: .string)
                    } label: {
                        Label(Loc.copyAllURLs(language), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Button(Loc.dismissAll(language)) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            pollingManager.clearAllNewVideos()
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                ForEach(pollingManager.newVideos, id: \.videoID) { video in
                    NewVideoRow(
                        video: video,
                        language: language,
                        onAddToQueue: onAddToQueue.map { callback in
                            { callback(video.url) }
                        },
                        onDismiss: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                pollingManager.dismissVideo(video)
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Channel list

    private var channelListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(spacing: 8) {
                Text(Loc.channels(language))
                    .font(.subheadline.weight(.semibold))

                Text("\(store.subscriptions.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())

                Spacer()

                // Delete button — only when items are selected
                if isSelecting && !selectedIDs.isEmpty {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label(Loc.deleteLabel(language), systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }

                Button {
                    pollingManager.checkNow()
                } label: {
                    Label(Loc.checkNow(language), systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                if !store.subscriptions.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSelecting.toggle()
                            if !isSelecting { selectedIDs.removeAll() }
                        }
                    } label: {
                        Text(isSelecting ? Loc.done(language) : Loc.selectAction(language))
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(isSelecting ? Color.accentColor : .secondary)
                }
            }

            // Channel rows
            if store.subscriptions.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text(Loc.noSubscriptionsTitle(language))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(Loc.noSubscriptionsHint(language))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 2) {
                    ForEach(store.subscriptions) { sub in
                        ChannelRow(
                            subscription: sub,
                            hasNewVideos: channelsWithNewVideos.contains(sub.channelName),
                            isSelecting: isSelecting,
                            isSelected: selectedIDs.contains(sub.id),
                            language: language,
                            onTapSelection: { toggleSelection(sub.id) },
                            onToggleEnabled: { store.toggleEnabled(id: sub.id) }
                        )
                    }
                }
            }
        }
        .alert(Loc.deleteSubscriptionsTitle(language), isPresented: $showDeleteConfirmation) {
            Button(Loc.cancelButton(language), role: .cancel) {}
            Button(
                Loc.deleteNChannels(selectedIDs.count, language),
                role: .destructive
            ) {
                deleteSelected()
            }
        } message: {
            let names = store.subscriptions
                .filter { selectedIDs.contains($0.id) }
                .map(\.channelName)
                .joined(separator: ", ")
            Text(Loc.removeConfirmation(names, language))
        }
    }

    // MARK: - Actions

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func deleteSelected() {
        withAnimation(.easeOut(duration: 0.2)) {
            for id in selectedIDs {
                store.remove(id: id)
            }
            selectedIDs.removeAll()
            if store.subscriptions.isEmpty {
                isSelecting = false
            }
        }
    }

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

// MARK: - New video row

private struct NewVideoRow: View {
    let video: FeedVideo
    var language: AppLanguage = .english
    var onAddToQueue: (() -> Void)? = nil
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

            if let videoURL = URL(string: video.url) {
                Link(destination: videoURL) {
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.borderless)
            }

            if let onAddToQueue {
                Button(action: onAddToQueue) {
                    Image(systemName: "plus.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
                .help(Loc.addVideoToQueue(language))
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(video.url, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(Loc.copyURLHelp(language))

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Channel row (iOS Messages style)

private struct ChannelRow: View {
    let subscription: ChannelSubscription
    let hasNewVideos: Bool
    let isSelecting: Bool
    let isSelected: Bool
    var language: AppLanguage = .english
    let onTapSelection: () -> Void
    let onToggleEnabled: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Selection circle — slides in from the left
            if isSelecting {
                Button(action: onTapSelection) {
                    ZStack {
                        Circle()
                            .strokeBorder(
                                isSelected ? Color.clear : Color.secondary.opacity(0.35),
                                lineWidth: 1.5
                            )
                            .background(
                                Circle().fill(isSelected ? Color.accentColor : Color.clear)
                            )
                            .frame(width: 20, height: 20)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.borderless)
                .padding(.trailing, 12)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // Blue dot — new videos indicator (always occupies space for alignment)
            Circle()
                .fill(hasNewVideos ? Color.accentColor : Color.clear)
                .frame(width: 10, height: 10)
                .padding(.trailing, 10)

            // Channel info
            VStack(alignment: .leading, spacing: 3) {
                Text(subscription.channelName)
                    .font(.body.weight(.medium))
                if let lastChecked = subscription.lastCheckedDate {
                    HStack(spacing: 0) {
                        Text(Loc.checkedPrefix(language))
                        Text(lastChecked, style: .relative)
                        Text(Loc.checkedSuffix(language))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            // Enable toggle
            Toggle(isOn: Binding(
                get: { subscription.isEnabled },
                set: { _ in onToggleEnabled() }
            )) {
                EmptyView()
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            isSelected && isSelecting
                ? Color.accentColor.opacity(0.10)
                : Color(nsColor: .controlBackgroundColor).opacity(0.5),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isSelected && isSelecting
                        ? Color.accentColor.opacity(0.3)
                        : Color.clear,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting { onTapSelection() }
        }
    }
}
