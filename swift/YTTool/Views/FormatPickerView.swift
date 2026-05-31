import SwiftUI

// MARK: - Column widths (shared between header and rows)

// Detailed mode: 7 video columns + 5 audio columns.
private enum VideoCol {
    static let id: CGFloat = 30
    static let res: CGFloat = 44
    static let codec: CGFloat = 44
    static let fps: CGFloat = 38
    static let bitrate: CGFloat = 50
    static let size: CGFloat = 60
    static let note: CGFloat = 66
}

private enum AudioCol {
    static let id: CGFloat = 36
    static let codec: CGFloat = 44
    static let bitrate: CGFloat = 50
    static let size: CGFloat = 60
    static let note: CGFloat = 66
}

// Simplified mode: fewer, wider columns.
private enum SimpleVideoCol {
    static let res: CGFloat = 60
    static let size: CGFloat = 70
    static let note: CGFloat = 80
}

private enum SimpleAudioCol {
    static let codec: CGFloat = 50
    static let size: CGFloat = 70
    static let quality: CGFloat = 110 // "Standard · 129k"
}

// MARK: - Selectable row style

private struct SelectableRowStyle: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
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
}

// MARK: - View

struct FormatPickerView: View {
    let probeState: ProbeState
    let playlistMode: PlaylistMode
    let isPlaylistURL: Bool
    var language: AppLanguage = .english
    var showTechnicalDetails: Bool = false
    @Binding var selectedVideo: VideoFormat?
    @Binding var selectedAudio: AudioFormat?
    @Binding var selectedSubtitle: SubtitleTrack?

    /// Minimum width for the video column so fixed-width items + spacing + padding fit.
    private var videoMinWidth: CGFloat {
        if showTechnicalDetails {
            let items = VideoCol.id + VideoCol.res + VideoCol.codec + VideoCol.fps
                + VideoCol.bitrate + VideoCol.size + VideoCol.note
            return items + 6 * 6 + 24 // 6 gaps + 12pt padding each side
        } else {
            let items = SimpleVideoCol.res + SimpleVideoCol.size + SimpleVideoCol.note
            return items + 2 * 6 + 24
        }
    }

    /// Minimum width for the audio column.
    private var audioMinWidth: CGFloat {
        if showTechnicalDetails {
            let items = AudioCol.id + AudioCol.codec + AudioCol.bitrate
                + AudioCol.size + AudioCol.note
            return items + 4 * 6 + 24
        } else {
            let items = SimpleAudioCol.codec + SimpleAudioCol.size + SimpleAudioCol.quality
            return items + 2 * 6 + 24
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Loc.formatsHeading(language))
                .font(.headline)

            switch probeState {
            case .idle:
                placeholder(idleMessage)
            case .loading:
                ProgressView(Loc.loadingFormats(language))
            case let .failure(error):
                placeholder(error.message)
            case let .success(mediaInfo):
                if isPlaylistURL, playlistMode.downloadsWholePlaylist {
                    placeholder(Loc.wholePlaylistSkips(language))
                } else {
                    formatColumns(mediaInfo: mediaInfo)
                }
            }
        }
    }

    @ViewBuilder
    private func formatColumns(mediaInfo: MediaInfo) -> some View {
        let hasSubs = !mediaInfo.subtitleTracks.isEmpty || !mediaInfo.autoSubtitleTracks.isEmpty
        let columns = HStack(alignment: .top, spacing: 16) {
            videoColumn(formats: mediaInfo.videoFormats)
                .frame(minWidth: videoMinWidth, maxWidth: .infinity, alignment: .topLeading)
            audioColumn(formats: mediaInfo.audioFormats)
                .frame(minWidth: audioMinWidth, maxWidth: .infinity, alignment: .topLeading)
            if hasSubs {
                subtitleColumn(
                    manual: mediaInfo.subtitleTracks,
                    auto: mediaInfo.autoSubtitleTracks
                )
            }
        }

        if showTechnicalDetails {
            ScrollView(.horizontal, showsIndicators: true) {
                columns
            }
        } else {
            columns
        }
    }

    private var idleMessage: String {
        if isPlaylistURL {
            switch playlistMode {
            case .onlyFirstItem:
                return Loc.probeFirstToInspect(language)
            case .wholePlaylistBestVideo, .wholePlaylistBestAudio:
                return Loc.wholePlaylistAuto(language)
            }
        }
        return Loc.probeToInspect(language)
    }

    // MARK: - Video column

    private func videoColumn(formats: [VideoFormat]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Loc.videoLabel(language))
                .font(.subheadline.weight(.semibold))

            if formats.isEmpty {
                placeholder(Loc.noVideoFormats(language))
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
    }

    @ViewBuilder
    private var videoHeader: some View {
        if showTechnicalDetails {
            HStack(spacing: 6) {
                Text("ID").frame(width: VideoCol.id, alignment: .leading)
                Text(Loc.colRes(language)).frame(width: VideoCol.res, alignment: .leading)
                Text(Loc.colCodec(language)).frame(width: VideoCol.codec, alignment: .leading)
                Text("FPS").frame(width: VideoCol.fps, alignment: .leading)
                Text(Loc.colBitrate(language)).frame(width: VideoCol.bitrate, alignment: .leading)
                Text(Loc.colSize(language)).frame(width: VideoCol.size, alignment: .leading)
                Text(Loc.colNote(language)).frame(width: VideoCol.note, alignment: .leading)
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
        } else {
            HStack(spacing: 6) {
                Text(Loc.colRes(language)).frame(width: SimpleVideoCol.res, alignment: .leading)
                Text(Loc.colSize(language)).frame(width: SimpleVideoCol.size, alignment: .leading)
                Text(Loc.colNote(language)).frame(width: SimpleVideoCol.note, alignment: .leading)
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
        }
    }

    private func videoRow(_ fmt: VideoFormat, isSelected: Bool) -> some View {
        Group {
            if showTechnicalDetails {
                HStack(spacing: 6) {
                    Text(fmt.id).lineLimit(1).frame(width: VideoCol.id, alignment: .leading)
                    Text(fmt.resolution).lineLimit(1).frame(width: VideoCol.res, alignment: .leading)
                    Text(fmt.friendlyCodec).lineLimit(1).frame(width: VideoCol.codec, alignment: .leading)
                    Text("\(fmt.fps)fps").lineLimit(1).frame(width: VideoCol.fps, alignment: .leading)
                    Text(fmt.formattedBitrate).lineLimit(1).frame(width: VideoCol.bitrate, alignment: .leading)
                    Text(fmt.formattedFileSize).lineLimit(1).frame(width: VideoCol.size, alignment: .leading)
                    Text(Loc.videoNote(fmt.note, language)).lineLimit(1).frame(width: VideoCol.note, alignment: .leading)
                }
            } else {
                HStack(spacing: 6) {
                    Text(fmt.resolution).lineLimit(1).frame(width: SimpleVideoCol.res, alignment: .leading)
                    Text(fmt.formattedFileSize).lineLimit(1).frame(width: SimpleVideoCol.size, alignment: .leading)
                    Text(Loc.videoNote(fmt.note, language)).lineLimit(1).frame(width: SimpleVideoCol.note, alignment: .leading)
                }
            }
        }
        .modifier(SelectableRowStyle(isSelected: isSelected))
    }

    // MARK: - Audio column

    private func audioColumn(formats: [AudioFormat]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Loc.audioLabel(language))
                .font(.subheadline.weight(.semibold))

            if formats.isEmpty {
                placeholder(Loc.noAudioFormats(language))
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
    }

    @ViewBuilder
    private var audioHeader: some View {
        if showTechnicalDetails {
            HStack(spacing: 6) {
                Text("ID").frame(width: AudioCol.id, alignment: .leading)
                Text(Loc.colCodec(language)).frame(width: AudioCol.codec, alignment: .leading)
                Text(Loc.colBitrate(language)).frame(width: AudioCol.bitrate, alignment: .leading)
                Text(Loc.colSize(language)).frame(width: AudioCol.size, alignment: .leading)
                Text(Loc.colNote(language)).frame(width: AudioCol.note, alignment: .leading)
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
        } else {
            HStack(spacing: 6) {
                Text(Loc.colCodec(language)).frame(width: SimpleAudioCol.codec, alignment: .leading)
                Text(Loc.colSize(language)).frame(width: SimpleAudioCol.size, alignment: .leading)
                Text(Loc.qualityLabel(language)).frame(width: SimpleAudioCol.quality, alignment: .leading)
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
        }
    }

    private func audioRow(_ fmt: AudioFormat, isSelected: Bool) -> some View {
        Group {
            if showTechnicalDetails {
                HStack(spacing: 6) {
                    Text(fmt.id).lineLimit(1).frame(width: AudioCol.id, alignment: .leading)
                    Text(fmt.friendlyCodec).lineLimit(1).frame(width: AudioCol.codec, alignment: .leading)
                    Text(fmt.formattedBitrate).lineLimit(1).frame(width: AudioCol.bitrate, alignment: .leading)
                    Text(fmt.formattedFileSize).lineLimit(1).frame(width: AudioCol.size, alignment: .leading)
                    Text(Loc.audioNote(fmt.note, language)).lineLimit(1).frame(width: AudioCol.note, alignment: .leading)
                }
            } else {
                HStack(spacing: 6) {
                    Text(fmt.friendlyCodec).lineLimit(1).frame(width: SimpleAudioCol.codec, alignment: .leading)
                    Text(fmt.formattedFileSize).lineLimit(1).frame(width: SimpleAudioCol.size, alignment: .leading)
                    Text(Loc.audioQualityBrief(fmt.note, kbps: fmt.bitrateKbps, language))
                        .lineLimit(1).frame(width: SimpleAudioCol.quality, alignment: .leading)
                }
            }
        }
        .modifier(SelectableRowStyle(isSelected: isSelected))
    }

    // MARK: - Subtitle column

    private func subtitleColumn(manual: [SubtitleTrack], auto: [SubtitleTrack]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Loc.subtitlesLabel(language))
                .font(.subheadline.weight(.semibold))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if !manual.isEmpty {
                        Text(Loc.manualSubs(language))
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
                        Text(Loc.autoSubs(language))
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
        .frame(minWidth: 170, idealWidth: 200, maxWidth: 240, alignment: .topLeading)
    }

    private func subtitleRow(_ track: SubtitleTrack, isSelected: Bool) -> some View {
        Text(track.displayName)
            .lineLimit(1)
            .modifier(SelectableRowStyle(isSelected: isSelected))
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
