import SwiftUI

struct AdvancedOptionsView: View {
    @Binding var audioTranscodeFormat: AudioTranscodeFormat
    @ObservedObject var state: AppState
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Audio transcode")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    Picker("Audio transcode", selection: $audioTranscodeFormat) {
                        ForEach(AudioTranscodeFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220, alignment: .leading)
                }

                settingsSummary
            }
            .padding(.top, 8)
        } label: {
            Text("Advanced options (optional)")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var settingsSummary: some View {
        let hasCookies = !state.cookiesFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasExtraArgs = !state.extraYtDlpArguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let engineLabel = state.downloaderPreference.label

        VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack(spacing: 16) {
                Label(engineLabel, systemImage: "gear")
                if hasCookies {
                    Label("Cookies set", systemImage: "checkmark.circle")
                }
                if hasExtraArgs {
                    Label("Extra args set", systemImage: "checkmark.circle")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("Change in Settings tab")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
