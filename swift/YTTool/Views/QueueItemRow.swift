import SwiftUI

struct QueueItemRow: View {
    @ObservedObject var item: QueueItem
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 16)

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
            Text("Pending")
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
                Text("Starting...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .completed:
            Text("Completed")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed:
            Text(item.error?.message ?? "Failed")
                .font(.caption)
                .foregroundStyle(.red)
        case .cancelled:
            Text("Cancelled")
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
            .help("Remove from queue")
        case .active:
            Button(action: onCancel) {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Cancel download")
        case .failed:
            Button(action: onRetry) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.orange)
            .help("Retry")
        case .completed, .cancelled:
            EmptyView()
        }
    }
}
