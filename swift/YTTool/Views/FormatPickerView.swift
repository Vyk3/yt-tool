import SwiftUI

struct FormatPickerView: View {
    let probeState: ProbeState
    @Binding var selectedVideo: VideoFormat?
    @Binding var selectedAudio: AudioFormat?

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
                    videoColumn(formats: mediaInfo.videoFormats)
                    audioColumn(formats: mediaInfo.audioFormats)
                }
            }
        }
    }

    // MARK: - Video column

    private func videoColumn(formats: [VideoFormat]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Video")
                .font(.subheadline.weight(.semibold))

            if formats.isEmpty {
                placeholder("No video formats detected.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(formats) { fmt in
                            formatRow(
                                text: fmt.displayLine,
                                isSelected: selectedVideo?.id == fmt.id
                            )
                            .onTapGesture {
                                if selectedVideo?.id == fmt.id {
                                    selectedVideo = nil
                                } else {
                                    selectedVideo = fmt
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Audio column

    private func audioColumn(formats: [AudioFormat]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audio")
                .font(.subheadline.weight(.semibold))

            if formats.isEmpty {
                placeholder("No audio formats detected.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(formats) { fmt in
                            formatRow(
                                text: fmt.displayLine,
                                isSelected: selectedAudio?.id == fmt.id
                            )
                            .onTapGesture {
                                if selectedAudio?.id == fmt.id {
                                    selectedAudio = nil
                                } else {
                                    selectedAudio = fmt
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Shared row

    private func formatRow(text: String, isSelected: Bool) -> some View {
        Text(text)
            .font(.callout.monospaced())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.25)
                    : Color.primary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: 1.5
                    )
            )
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
