import SwiftUI

struct FormatPickerView: View {
    let probeState: ProbeState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Formats")
                .font(.headline)

            switch probeState {
            case .idle:
                placeholder("Probe a URL to inspect available formats.")
            case .loading:
                ProgressView("Loading formats…")
            case .failure(let error):
                placeholder(error.message)
            case .success(let mediaInfo):
                HStack(alignment: .top, spacing: 16) {
                    formatColumn(
                        title: "Video",
                        items: mediaInfo.videoFormats.map(\.displayLine)
                    )
                    formatColumn(
                        title: "Audio",
                        items: mediaInfo.audioFormats.map(\.displayLine)
                    )
                }
            }
        }
    }

    private func formatColumn(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            if items.isEmpty {
                placeholder("No \(title.lowercased()) formats detected.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(items, id: \.self) { item in
                            Text(item)
                                .font(.callout.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 24)
            .padding(.horizontal, 12)
            .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }
}
