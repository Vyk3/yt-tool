import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: DownloadHistoryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Download History")
                    .font(.title2.weight(.semibold))
                Spacer()
                if !store.entries.isEmpty {
                    Button("Clear All") { store.clear() }
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 8)
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            if store.entries.isEmpty {
                Spacer()
                Text("No downloads yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(store.entries.reversed()) { entry in
                    historyRow(entry)
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 560, height: 400)
    }

    private func historyRow(_ entry: DownloadHistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(entry.succeeded ? .green : .red)
                .font(.title3)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title ?? entry.url)
                    .lineLimit(1)
                    .font(.callout.weight(.medium))

                HStack(spacing: 8) {
                    Text(entry.dateCompleted.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let bytes = entry.estimatedSizeBytes {
                        Text(formatBytes(bytes))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let path = entry.outputPath {
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            if entry.succeeded, let path = entry.outputPath,
               FileManager.default.fileExists(atPath: path) {
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: path)]
                    )
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.callout)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return String(format: "%.0f KB", mb * 1024)
    }
}
