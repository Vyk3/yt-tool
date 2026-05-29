import SwiftUI

struct AdvancedOptionsView: View {
    @Binding var audioTranscodeFormat: AudioTranscodeFormat
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
            }
            .padding(.top, 8)
        } label: {
            Text("Advanced options (optional)")
                .font(.headline)
        }
    }
}
