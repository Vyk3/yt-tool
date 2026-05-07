import SwiftUI

struct QueueView: View {
    @ObservedObject var queue: DownloadQueue
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Queue (\(queue.items.count) items)")
                    .font(.headline)

                Spacer()

                if !queue.items.isEmpty {
                    if queue.isProcessing {
                        Button("Stop", action: queue.stopProcessing)
                    } else {
                        Button("Start", action: onStart)
                            .disabled(queue.items.allSatisfy(\.status.isTerminal))
                    }

                    Button("Clear done", action: queue.clearCompleted)
                        .disabled(!queue.items.contains { $0.status.isTerminal })
                }
            }

            if queue.items.isEmpty {
                Text("No items in queue. Paste URLs above and click Add to Queue.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                List {
                    ForEach(queue.items) { item in
                        QueueItemRow(
                            item: item,
                            onCancel: { queue.cancelItem(item) },
                            onRetry: { queue.retryItem(item) },
                            onRemove: { queue.removeItem(item) }
                        )
                    }
                    .onMove { source, destination in
                        queue.moveItem(from: source, to: destination)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .frame(minHeight: 120, maxHeight: 300)
            }
        }
    }
}
