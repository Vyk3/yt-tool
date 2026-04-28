import SwiftUI

// MARK: - Column widths (shared between header and rows)

// Budget: content area ≈ 394pt per column (900pt window, 24pt outer padding, 16pt HStack gap).
// 7 video columns + 6 spacings(6) + padding(24) = 332 + 36 + 24 = 392pt ≤ 394pt.
private enum VideoCol {
    static let id: CGFloat      = 30
    static let res: CGFloat     = 44
    static let codec: CGFloat   = 44
    static let fps: CGFloat     = 38
    static let bitrate: CGFloat = 50
    static let size: CGFloat    = 60
    static let note: CGFloat    = 66   // "w/ audio" = 8 chars × 7.6pt ≈ 61pt; 66pt fits
}

private enum AudioCol {
    static let id: CGFloat      = 36
    static let codec: CGFloat   = 44
    static let bitrate: CGFloat = 50
    static let size: CGFloat    = 60
    static let note: CGFloat    = 66
}

// MARK: - View

struct FormatPickerView: View {
    let probeState: ProbeState
    let playlistMode: PlaylistMode
    let isPlaylistURL: Bool
    @Binding var selectedVideo: VideoFormat?
    @Binding var selectedAudio: AudioFormat?
    @Binding var selectedSubtitle: SubtitleTrack?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Formats")
                .font(.headline)

            switch probeState {
            case .idle:
                placeholder(idleMessage)
            case .loading:
                ProgressView("Loading formats…")
            case .failure(let error):
                placeholder(error.message)
            case .success(let mediaInfo):
                if isPlaylistURL && playlistMode.downloadsWholePlaylist {
                    placeholder("Whole playlist mode skips per-item format selection and downloads every item automatically.")
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        videoColumn(formats: mediaInfo.videoFormats)
                        audioColumn(formats: mediaInfo.audioFormats)
                        let hasSubs = !mediaInfo.subtitleTracks.isEmpty || !mediaInfo.autoSubtitleTracks.isEmpty
                        if hasSubs {
                            subtitleColumn(
                                manual: mediaInfo.subtitleTracks,
                                auto: mediaInfo.autoSubtitleTracks
                            )
                        }
                    }
                }
            }
        }
    }

    private var idleMessage: String {
        if isPlaylistURL {
            switch playlistMode {
            case .onlyFirstItem:
                return "Probe the first item to inspect formats."
            case .wholePlaylistBestVideo, .wholePlaylistBestAudio:
                return "Whole playlist mode downloads every item automatically."
            }
        }
        return "Probe a URL to inspect available formats."
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
        HStack(spacing: 6) {
            Text("ID")     .frame(width: VideoCol.id,      alignment: .leading)
            Text("Res")    .frame(width: VideoCol.res,     alignment: .leading)
            Text("Codec")  .frame(width: VideoCol.codec,   alignment: .leading)
            Text("FPS")    .frame(width: VideoCol.fps,     alignment: .leading)
            Text("Bitrate").frame(width: VideoCol.bitrate, alignment: .leading)
            Text("Size")   .frame(width: VideoCol.size,    alignment: .leading)
            Text("Note")   .frame(width: VideoCol.note,    alignment: .leading)
        }
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
    }

    private func videoRow(_ fmt: VideoFormat, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Text(fmt.id)               .lineLimit(1).frame(width: VideoCol.id,      alignment: .leading)
            Text(fmt.resolution)       .lineLimit(1).frame(width: VideoCol.res,     alignment: .leading)
            Text(fmt.friendlyCodec)    .lineLimit(1).frame(width: VideoCol.codec,   alignment: .leading)
            Text("\(fmt.fps)fps")      .lineLimit(1).frame(width: VideoCol.fps,     alignment: .leading)
            Text(fmt.formattedBitrate) .lineLimit(1).frame(width: VideoCol.bitrate, alignment: .leading)
            Text(fmt.formattedFileSize).lineLimit(1).frame(width: VideoCol.size,    alignment: .leading)
            Text(fmt.note)             .lineLimit(1).frame(width: VideoCol.note,    alignment: .leading)
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
        HStack(spacing: 6) {
            Text("ID")     .frame(width: AudioCol.id,      alignment: .leading)
            Text("Codec")  .frame(width: AudioCol.codec,   alignment: .leading)
            Text("Bitrate").frame(width: AudioCol.bitrate, alignment: .leading)
            Text("Size")   .frame(width: AudioCol.size,    alignment: .leading)
            Text("Note")   .frame(width: AudioCol.note,    alignment: .leading)
        }
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
    }

    private func audioRow(_ fmt: AudioFormat, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Text(fmt.id)               .lineLimit(1).frame(width: AudioCol.id,      alignment: .leading)
            Text(fmt.friendlyCodec)    .lineLimit(1).frame(width: AudioCol.codec,   alignment: .leading)
            Text(fmt.formattedBitrate) .lineLimit(1).frame(width: AudioCol.bitrate, alignment: .leading)
            Text(fmt.formattedFileSize).lineLimit(1).frame(width: AudioCol.size,    alignment: .leading)
            Text(fmt.note)             .lineLimit(1).frame(width: AudioCol.note,    alignment: .leading)
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

    // MARK: - Subtitle column

    private func subtitleColumn(manual: [SubtitleTrack], auto: [SubtitleTrack]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Subtitles")
                .font(.subheadline.weight(.semibold))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if !manual.isEmpty {
                        Text("Manual")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                        ForEach(manual) { track in
                            subtitleRow(track, isSelected: selectedSubtitle?.id == track.id)
                                .onTapGesture {
                                    selectedSubtitle = selectedSubtitle?.id == track.id ? nil : track
                                }
                        }
                    }
                    if !auto.isEmpty {
                        Text("Auto-generated")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                        ForEach(auto) { track in
                            subtitleRow(track, isSelected: selectedSubtitle?.id == track.id)
                                .onTapGesture {
                                    selectedSubtitle = selectedSubtitle?.id == track.id ? nil : track
                                }
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func subtitleRow(_ track: SubtitleTrack, isSelected: Bool) -> some View {
        Text(track.displayName)
            .font(.callout.monospaced())
            .lineLimit(1)
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
