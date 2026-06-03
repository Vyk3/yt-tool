import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: DownloadHistoryStore
    var language: AppLanguage = .english
    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(Loc.downloadHistory(language))
                    .font(.title2.weight(.semibold))
                Spacer()
                if !store.entries.isEmpty {
                    Button(Loc.clearAll(language)) { showClearConfirmation = true }
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 8)
                }
                Button(Loc.done(language)) { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .alert(Loc.clearHistoryTitle(language), isPresented: $showClearConfirmation) {
                Button(Loc.clearAll(language), role: .destructive) { store.clear() }
                Button(Loc.cancelButton(language), role: .cancel) {}
            } message: {
                Text(Loc.clearHistoryMessage(language))
            }

            Divider()

            if store.entries.isEmpty {
                Spacer()
                Text(Loc.noDownloadsYet(language))
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
               FileManager.default.fileExists(atPath: path)
            {
                let fileURL = URL(fileURLWithPath: path)
                Button(Loc.openFolder(language)) {
                    NSWorkspace.shared.open(fileURL.deletingLastPathComponent())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.callout)

                Button(Loc.reveal(language)) {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.callout)
            }

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    store.remove(id: entry.id)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
