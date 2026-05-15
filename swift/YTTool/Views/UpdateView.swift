import SwiftUI

struct UpdateView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("yt-dlp")
                .font(.headline)

            if let version = state.currentYtDlpVersion {
                LabeledContent("Current version", value: "\(version) (\(state.ytDlpSource))")
            } else {
                LabeledContent("Current version", value: "Unknown")
            }

            LabeledContent("Channel") {
                Picker("Channel", selection: $state.updateChannel) {
                    ForEach(UpdateChannel.allCases) { channel in
                        Text(channel.label).tag(channel)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 120)
            }

            Toggle("Check for yt-dlp updates on launch", isOn: $state.autoCheckForUpdates)

            updateStatusView
        }
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch state.updateState {
        case .idle:
            Button("Check for Updates", action: state.checkForUpdate)

        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking...")
            }

        case let .available(current, latest):
            VStack(alignment: .leading, spacing: 6) {
                Text("Update available: \(current) \u{2192} \(latest)")
                    .foregroundStyle(.orange)
                Button("Install Update", action: state.installUpdate)
            }

        case let .upToDate(version):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Up to date (\(version))")
                }
                Button("Check Again", action: state.checkForUpdate)
            }

        case let .downloading(progress):
            VStack(alignment: .leading, spacing: 4) {
                Text("Downloading...")
                ProgressView(value: progress)
                    .frame(maxWidth: 200)
            }

        case .verifying:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Verifying and installing...")
            }

        case let .completed(newVersion):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Updated to \(newVersion)")
                }
                Button("Check Again", action: state.checkForUpdate)
            }

        case let .failed(error):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(error.message)
                }
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Retry", action: state.checkForUpdate)
            }
        }
    }
}
