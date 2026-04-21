import AppKit
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
            stagePanel(
                title: "Preparing",
                subtitle: "Building the yt-dlp command and starting the process.",
                body: commandPreview,
                tint: .orange
            )

        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    stageHeader(
                        title: "Downloading",
                        subtitle: "The active transfer is in progress.",
                        tint: .blue
                    )
                    Spacer()
                    Text(progressPercentText(progress))
                        .font(.title3.monospacedDigit().weight(.semibold))
                }

                ProgressView(value: progress.percentComplete)
                    .progressViewStyle(.linear)

                if let details = progressDetails(progress.summaryLine) {
                    HStack(spacing: 12) {
                        progressMetric("Size", details.size)
                        progressMetric("Speed", details.speed)
                        if let eta = details.eta {
                            progressMetric("ETA", eta)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))

        case .succeeded(let outputURL):
            successPanel(outputURL)

        case .failed(let error):
            failurePanel(error)

        case .cancelled:
            stagePanel(
                title: "Cancelled",
                subtitle: "The active process tree was terminated.",
                body: "You can adjust the format or output folder, then start a new download.",
                tint: .orange
            )
        }
    }

    private func successPanel(_ outputURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            stageHeader(
                title: "Completed ✓",
                subtitle: "Choose what to do with the finished file.",
                tint: .green
            )

            HStack(spacing: 10) {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                }
                .buttonStyle(.borderedProminent)

                Button("Open Folder") {
                    NSWorkspace.shared.open(outputURL.deletingLastPathComponent())
                }
                .buttonStyle(.bordered)

                Button("Copy File Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(outputURL.path(percentEncoded: false), forType: .string)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }

    private func failurePanel(_ error: AppError) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            stageHeader(
                title: "Failed",
                subtitle: "The download stopped before completion.",
                tint: .red
            )

            detailBlock(label: "Reason", value: error.message)

            if let suggestion = error.recoverySuggestion?.trimmingCharacters(in: .whitespacesAndNewlines),
               !suggestion.isEmpty {
                detailBlock(label: "Try this", value: suggestion)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }

    private func stagePanel(title: String, subtitle: String, body: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            stageHeader(title: title, subtitle: subtitle, tint: tint)
            Text(body)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }

    private func stageHeader(title: String, subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func detailBlock(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
    }

    private func progressPercentText(_ progress: DownloadProgress) -> String {
        "\(Int((progress.percentComplete * 100).rounded()))%"
    }

    private func progressMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospaced())
        }
    }

    private func progressDetails(_ summaryLine: String) -> (size: String, speed: String, eta: String?)? {
        let text = summaryLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ofRange = text.range(of: " of "),
              let atRange = text.range(of: " at ", range: ofRange.upperBound..<text.endIndex)
        else {
            return nil
        }

        let size = text[ofRange.upperBound..<atRange.lowerBound].trimmingCharacters(in: .whitespaces)
        let etaRange = text.range(of: " ETA ", range: atRange.upperBound..<text.endIndex)

        if let etaRange {
            let speed = text[atRange.upperBound..<etaRange.lowerBound].trimmingCharacters(in: .whitespaces)
            let eta = text[etaRange.upperBound..<text.endIndex].trimmingCharacters(in: .whitespaces)
            return (size: size, speed: speed, eta: eta.isEmpty ? nil : eta)
        }

        let speed = text[atRange.upperBound..<text.endIndex].trimmingCharacters(in: .whitespaces)
        return (size: size, speed: speed, eta: nil)
    }
}
