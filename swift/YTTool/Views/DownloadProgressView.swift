import SwiftUI

struct DownloadProgressView: View {
    let downloadState: DownloadState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Download")
                .font(.headline)

            switch downloadState {
            case .idle:
                Text("Download workflow is not connected yet.")
                    .foregroundStyle(.secondary)
            case .preparing(let commandPreview):
                labeledPanel(title: "Preparing", body: commandPreview)
            case .downloading(let progress):
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: progress.percentComplete)
                    Text(progress.summaryLine)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                }
            case .succeeded(let outputURL):
                labeledPanel(title: "Completed", body: outputURL.path(percentEncoded: false))
            case .failed(let error):
                labeledPanel(title: "Failed", body: error.message)
            case .cancelled:
                labeledPanel(title: "Cancelled", body: "The active process tree was terminated.")
            }
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
