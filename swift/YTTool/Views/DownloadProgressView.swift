import SwiftUI

struct DownloadProgressView: View {
    let downloadState: DownloadState
    let canDownload: Bool
    let isDownloading: Bool
    let onDownload: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Download")
                    .font(.headline)
                Spacer()
                actionButton
            }

            statusContent
        }
    }

    // MARK: - Action button

    @ViewBuilder
    private var actionButton: some View {
        if isDownloading {
            Button(role: .destructive, action: onCancel) {
                Label("Cancel", systemImage: "stop.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        } else {
            Button(action: onDownload) {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canDownload)
        }
    }

    // MARK: - Status body

    @ViewBuilder
    private var statusContent: some View {
        switch downloadState {
        case .idle:
            Text(canDownload
                 ? "Ready to download. Press Download to start."
                 : "Select a format and output folder to enable download.")
                .foregroundStyle(.secondary)

        case .preparing(let commandPreview):
            labeledPanel(title: "Preparing…", body: commandPreview)

        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress.percentComplete)
                    .progressViewStyle(.linear)
                Text(progress.summaryLine)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(12)
            .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))

        case .succeeded(let outputURL):
            labeledPanel(
                title: "Completed ✓",
                body: outputURL.path(percentEncoded: false)
            )

        case .failed(let error):
            labeledPanel(title: "Failed", body: "\(error.message)\n\(error.recoverySuggestion ?? "")")

        case .cancelled:
            labeledPanel(title: "Cancelled", body: "The active process tree was terminated.")
        }
    }

    private func labeledPanel(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(body)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }
}
