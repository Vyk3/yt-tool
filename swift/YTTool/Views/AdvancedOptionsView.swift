import SwiftUI

struct AdvancedOptionsView: View {
    @Binding var audioTranscodeFormat: AudioTranscodeFormat
    @Binding var cookiesFilePath: String
    @Binding var extraYtDlpArguments: String
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

                VStack(alignment: .leading, spacing: 6) {
                    Text("Cookies file path")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("/path/to/cookies.txt", text: $cookiesFilePath)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1)
                    Text("Optional. The path must exist and be readable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Extra yt-dlp arguments")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("--download-sections \"*00:30-01:00\"", text: $extraYtDlpArguments)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1)
                    Text("Optional. Passed through after validation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        } label: {
            Text("Advanced options (optional)")
                .font(.headline)
        }
    }
}
