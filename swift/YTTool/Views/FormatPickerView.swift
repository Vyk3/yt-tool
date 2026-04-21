import SwiftUI

// MARK: - Column widths (shared between header and rows)

private enum VideoCol {
    static let id: CGFloat      = 52
    static let res: CGFloat     = 55
    static let codec: CGFloat   = 60
    static let fps: CGFloat     = 48
    static let bitrate: CGFloat = 62
    static let size: CGFloat    = 76
    // note: .infinity
}

private enum AudioCol {
    static let id: CGFloat      = 52
    static let codec: CGFloat   = 60
    static let bitrate: CGFloat = 62
    static let size: CGFloat    = 76
    // note: .infinity
}

// MARK: - View

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
        VStack(alignment: .leading, spacing: 6) {
            Text("Video")
                .font(.subheadline.weight(.semibold))

            if formats.isEmpty {
                placeholder("No video formats detected.")
            } else {
                videoHeader
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(formats) { fmt in
                            videoRow(fmt, isSelected: selectedVideo?.id == fmt.id)
                                .onTapGesture {
                                    selectedVideo = selectedVideo?.id == fmt.id ? nil : fmt
                                }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var videoHeader: some View {
        HStack(spacing: 8) {
            Text("ID")     .frame(width: VideoCol.id,      alignment: .leading)
            Text("Res")    .frame(width: VideoCol.res,     alignment: .leading)
            Text("Codec")  .frame(width: VideoCol.codec,   alignment: .leading)
            Text("FPS")    .frame(width: VideoCol.fps,     alignment: .leading)
            Text("Bitrate").frame(width: VideoCol.bitrate, alignment: .leading)
            Text("Size")   .frame(width: VideoCol.size,    alignment: .leading)
            Text("Audio")  .frame(maxWidth: .infinity,     alignment: .leading)
        }
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
    }

    private func videoRow(_ fmt: VideoFormat, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Text(fmt.id)               .frame(width: VideoCol.id,      alignment: .leading)
            Text(fmt.resolution)       .frame(width: VideoCol.res,     alignment: .leading)
            Text(fmt.friendlyCodec)    .frame(width: VideoCol.codec,   alignment: .leading)
            Text("\(fmt.fps)fps")      .frame(width: VideoCol.fps,     alignment: .leading)
            Text(fmt.formattedBitrate) .frame(width: VideoCol.bitrate, alignment: .leading)
            Text(fmt.formattedFileSize).frame(width: VideoCol.size,    alignment: .leading)
            Text(fmt.note)             .frame(maxWidth: .infinity,     alignment: .leading)
        }
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
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
    }

    // MARK: - Audio column

    private func audioColumn(formats: [AudioFormat]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Audio")
                .font(.subheadline.weight(.semibold))

            if formats.isEmpty {
                placeholder("No audio formats detected.")
            } else {
                audioHeader
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(formats) { fmt in
                            audioRow(fmt, isSelected: selectedAudio?.id == fmt.id)
                                .onTapGesture {
                                    selectedAudio = selectedAudio?.id == fmt.id ? nil : fmt
                                }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var audioHeader: some View {
        HStack(spacing: 8) {
            Text("ID")     .frame(width: AudioCol.id,      alignment: .leading)
            Text("Codec")  .frame(width: AudioCol.codec,   alignment: .leading)
            Text("Bitrate").frame(width: AudioCol.bitrate, alignment: .leading)
            Text("Size")   .frame(width: AudioCol.size,    alignment: .leading)
            Text("Note")   .frame(maxWidth: .infinity,     alignment: .leading)
        }
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
    }

    private func audioRow(_ fmt: AudioFormat, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Text(fmt.id)               .frame(width: AudioCol.id,      alignment: .leading)
            Text(fmt.friendlyCodec)    .frame(width: AudioCol.codec,   alignment: .leading)
            Text(fmt.formattedBitrate) .frame(width: AudioCol.bitrate, alignment: .leading)
            Text(fmt.formattedFileSize).frame(width: AudioCol.size,    alignment: .leading)
            Text(fmt.note)             .frame(maxWidth: .infinity,     alignment: .leading)
        }
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
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
    }

    // MARK: - Placeholder

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 24)
            .padding(.horizontal, 12)
            .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }
}
