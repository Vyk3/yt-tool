import SwiftUI

struct UpdateView: View {
    @ObservedObject var state: AppState

    /// When embedded in SettingsTabView the section header is provided externally.
    var showsHeader = true

    private var lang: AppLanguage { state.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsHeader {
                Text("yt-dlp")
                    .font(.headline)
            }

            if let version = state.currentYtDlpVersion {
                LabeledContent(Loc.currentVersionLabel(lang), value: "\(version) (\(state.ytDlpSource))")
            } else {
                LabeledContent(Loc.currentVersionLabel(lang), value: "Unknown")
            }

            LabeledContent(Loc.channelLabel(lang)) {
                Picker(Loc.channelLabel(lang), selection: $state.updateChannel) {
                    ForEach(UpdateChannel.allCases) { channel in
                        Text(channel.label).tag(channel)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 120)
            }

            Toggle(Loc.autoCheckYtDlp(lang), isOn: $state.autoCheckForUpdates)

            updateStatusView
        }
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch state.updateState {
        case .idle:
            Button(Loc.checkForUpdates(lang), action: state.checkForUpdate)

        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(Loc.checking(lang))
            }

        case let .available(current, latest):
            VStack(alignment: .leading, spacing: 6) {
                Text(Loc.updateAvailable(current, latest, lang))
                    .foregroundStyle(.orange)
                Button(Loc.installUpdate(lang), action: state.installUpdate)
            }

        case let .upToDate(version):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(Loc.upToDate(version, lang))
                }
                Button(Loc.checkAgain(lang), action: state.checkForUpdate)
            }

        case let .downloading(progress):
            VStack(alignment: .leading, spacing: 4) {
                Text(Loc.downloadingUpdate(lang))
                ProgressView(value: progress)
                    .frame(maxWidth: 200)
            }

        case .verifying:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(Loc.verifyingInstalling(lang))
            }

        case let .completed(newVersion):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(Loc.updatedTo(newVersion, lang))
                }
                Button(Loc.checkAgain(lang), action: state.checkForUpdate)
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
                Button(Loc.retry(lang), action: state.checkForUpdate)
            }
        }
    }
}
