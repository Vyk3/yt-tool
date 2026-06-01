import SwiftUI

struct QueueItemRow: View {
    @ObservedObject var item: QueueItem
    var language: AppLanguage = .english
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 16)

            ThumbnailView(
                url: item.thumbnailURL,
                targetSize: CGSize(width: 64, height: 36)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title ?? item.url)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.callout)

                statusDetail
            }

            Spacer(minLength: 0)

            actions
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .active:
            Image(systemName: "circle.fill")
                .foregroundStyle(.blue)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusDetail: some View {
        switch item.status {
        case .pending:
            Text(Loc.queuePending(language))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .active:
            if let progress = item.downloadProgress {
                HStack(spacing: 8) {
                    ProgressView(value: progress.percentComplete, total: 100)
                        .frame(maxWidth: 160)
                    Text("\(Int(progress.percentComplete))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(Loc.queueStarting(language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .completed:
            Text(Loc.queueCompleted(language))
                .font(.caption)
                .foregroundStyle(.green)
        case .failed:
            Text(item.error?.message ?? Loc.queueItemFailed(language))
                .font(.caption)
                .foregroundStyle(.red)
        case .cancelled:
            Text(Loc.queueItemCancelled(language))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch item.status {
        case .pending:
            Button(action: onRemove) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(Loc.queueRemoveHelp(language))
        case .active:
            Button(action: onCancel) {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(Loc.queueCancelHelp(language))
        case .failed:
            Button(action: onRetry) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.orange)
            .help(Loc.queueRetryHelp(language))
        case .completed:
            EmptyView()
        case .cancelled:
            HStack(spacing: 8) {
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.orange)
                .help(Loc.queueRetryHelp(language))

                Button(action: onRemove) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(Loc.queueRemoveHelp(language))
            }
        }
    }
}
