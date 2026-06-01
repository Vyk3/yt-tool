import AppKit
import SwiftUI

struct DownloadProgressView: View {
    let downloadState: DownloadState
    let canDownload: Bool
    let showsNoSelectableFormatsHint: Bool
    let hasOutputFolder: Bool
    let isDownloading: Bool
    let ffmpegWarningMessage: String?
    var language: AppLanguage = .english
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onReset: () -> Void
    let onRetry: () -> Void
    @State private var isShowingFFmpegWarning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Loc.downloadHeading(language))
                    .font(.headline)
                if let ffmpegWarningMessage {
                    ffmpegWarningButton(message: ffmpegWarningMessage)
                }
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
                Label(Loc.cancelButton(language), systemImage: "stop.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        } else {
            Button(action: onDownload) {
                Label(Loc.downloadButton(language), systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canDownload)
        }
    }

    private func ffmpegWarningButton(message: String) -> some View {
        Button {
            isShowingFFmpegWarning.toggle()
        } label: {
            Label(Loc.ffmpegUnavailable(language), systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingFFmpegWarning, arrowEdge: .top) {
            Text(message)
                .font(.callout)
                .frame(width: 280, alignment: .leading)
                .padding(12)
        }
        .help(Loc.ffmpegMissingHelp(language))
    }

    // MARK: - Status body

    @ViewBuilder
    private var statusContent: some View {
        switch downloadState {
        case .idle:
            if showsNoSelectableFormatsHint {
                Text(canDownload ? Loc.noFormatsCanDownload(language) : Loc.noFormatsNeedFolder(language))
                    .foregroundStyle(.secondary)
            } else if canDownload {
                Text(Loc.readyToDownload(language))
                    .foregroundStyle(.secondary)
            } else if !hasOutputFolder {
                Text(Loc.needFolderHint(language))
                    .foregroundStyle(.secondary)
            } else {
                Text(Loc.needFormatHint(language))
                    .foregroundStyle(.secondary)
            }

        case let .preparing(commandPreview):
            stagePanel(
                title: Loc.stagePreparing(language),
                subtitle: Loc.stagePreparingSub(language),
                body: commandPreview,
                tint: .orange
            )

        case let .downloading(progress):
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    stageHeader(
                        title: Loc.stageDownloading(language),
                        subtitle: Loc.stageDownloadingSub(language),
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
                        progressMetric(Loc.sizeLabel(language), details.size)
                        progressMetric(Loc.speedLabel(language), details.speed)
                        if let eta = details.eta {
                            progressMetric(Loc.etaLabel(language), eta)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))

        case let .succeeded(outputURL):
            successPanel(outputURL)

        case let .failed(error):
            failurePanel(error)

        case .cancelled:
            cancelledPanel
        }
    }

    private func successPanel(_ outputURL: URL) -> some View {
        let isDirectory = isDirectoryURL(outputURL)

        return VStack(alignment: .leading, spacing: 10) {
            stageHeader(
                title: Loc.stageCompleted(language),
                subtitle: isDirectory
                    ? Loc.stageCompletedSubDir(language)
                    : Loc.stageCompletedSubFile(language),
                tint: .green
            )

            HStack(spacing: 10) {
                Button(Loc.revealInFinder(language)) {
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                }
                .buttonStyle(.borderedProminent)

                Button(Loc.openFolder(language)) {
                    NSWorkspace.shared.open(isDirectory ? outputURL : outputURL.deletingLastPathComponent())
                }
                .buttonStyle(.bordered)

                Button(isDirectory ? Loc.copyFolderPath(language) : Loc.copyFilePath(language)) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(outputURL.path(percentEncoded: false), forType: .string)
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(Loc.newDownload(language)) {
                    onReset()
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
                title: Loc.stageFailed(language),
                subtitle: Loc.stageFailedSub(language),
                tint: .red
            )

            detailBlock(label: Loc.reasonLabel(language), value: error.message)

            if let suggestion = error.recoverySuggestion?.trimmingCharacters(in: .whitespacesAndNewlines),
               !suggestion.isEmpty
            {
                detailBlock(label: Loc.tryThisLabel(language), value: suggestion)
            }

            HStack {
                Spacer()
                Button(Loc.retryDownload(language)) { onRetry() }
                    .buttonStyle(.bordered)
                Button(Loc.newDownload(language)) { onReset() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }

    private var cancelledPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            stageHeader(
                title: Loc.stageCancelled(language),
                subtitle: Loc.stageCancelledSub(language),
                tint: .orange
            )

            Text(Loc.cancelledHint(language))
                .font(.callout.monospaced())
                .textSelection(.enabled)

            HStack {
                Spacer()
                Button(Loc.retryDownload(language)) { onRetry() }
                    .buttonStyle(.bordered)
                Button(Loc.newDownload(language)) { onReset() }
                    .buttonStyle(.bordered)
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
              let atRange = text.range(of: " at ", range: ofRange.upperBound ..< text.endIndex)
        else {
            return nil
        }

        let size = text[ofRange.upperBound ..< atRange.lowerBound].trimmingCharacters(in: .whitespaces)
        let etaRange = text.range(of: " ETA ", range: atRange.upperBound ..< text.endIndex)

        if let etaRange {
            let speed = text[atRange.upperBound ..< etaRange.lowerBound].trimmingCharacters(in: .whitespaces)
            let eta = text[etaRange.upperBound ..< text.endIndex].trimmingCharacters(in: .whitespaces)
            return (size: size, speed: speed, eta: eta.isEmpty ? nil : eta)
        }

        let speed = text[atRange.upperBound ..< text.endIndex].trimmingCharacters(in: .whitespaces)
        return (size: size, speed: speed, eta: nil)
    }

    private func isDirectoryURL(_ url: URL) -> Bool {
        if url.hasDirectoryPath {
            return true
        }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true
    }
}
