import SwiftUI

struct QueueView: View {
    @ObservedObject var queue: DownloadQueue
    var language: AppLanguage = .english
    let onStart: () -> Void

    private var completedCount: Int { queue.items.filter { $0.status == .completed }.count }
    private var failedCount: Int { queue.items.filter { $0.status == .failed }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Loc.queueCount(queue.items.count, language))
                    .font(.headline)

                if queue.isProcessing || completedCount > 0 || failedCount > 0, !queue.items.isEmpty {
                    Text(Loc.queueProgress(completedCount, queue.items.count, failedCount, language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !queue.items.isEmpty {
                    if queue.isProcessing {
                        Button(Loc.queueStop(language), action: queue.stopProcessing)
                    } else {
                        Button(Loc.queueStart(language), action: onStart)
                            .disabled(queue.items.allSatisfy(\.status.isTerminal))
                    }

                    Button(Loc.queueClearDone(language), action: queue.clearCompleted)
                        .disabled(!queue.items.contains { $0.status.isTerminal })
                }
            }

            if queue.items.isEmpty {
                Text(Loc.queueEmpty(language))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(queue.items.enumerated()), id: \.element.id) { index, item in
                            QueueItemRow(
                                item: item,
                                language: language,
                                onCancel: { queue.cancelItem(item) },
                                onRetry: { queue.retryItem(item) },
                                onRemove: { queue.removeItem(item) }
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                index.isMultiple(of: 2)
                                    ? Color.clear
                                    : Color.primary.opacity(0.03),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                        }
                    }
                }
                .frame(minHeight: min(max(CGFloat(queue.items.count) * 52, 80), 300), maxHeight: 300)
            }
        }
    }
}
