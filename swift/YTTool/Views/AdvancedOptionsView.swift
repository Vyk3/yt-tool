import AppKit
import SwiftUI

struct AdvancedOptionsView: View {
    @Binding var audioTranscodeFormat: AudioTranscodeFormat
    @ObservedObject var state: AppState
    @State private var expanded = false
    private var lang: AppLanguage { state.language }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(Loc.audioTranscode(lang))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    Picker(Loc.audioTranscode(lang), selection: $audioTranscodeFormat) {
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
            Text(Loc.advancedOptions(lang))
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
                    Label(Loc.cookiesSet(lang), systemImage: "checkmark.circle")
                }
                if hasExtraArgs {
                    Label(Loc.extraArgsSet(lang), systemImage: "checkmark.circle")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button {
                state.appMode = .settings
            } label: {
                Text(Loc.changeInSettings(lang))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
    }
}
