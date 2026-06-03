import SwiftUI
import UniformTypeIdentifiers

struct URLInputView: View {
    @Binding var inputURL: String
    @Binding var playlistConfig: PlaylistConfig
    let probeState: ProbeState
    let selectedDirectory: URL?
    let showsPlaylistModePicker: Bool
    let showsPlaylistVideoQualityStrategy: Bool
    let showsPlaylistAudioQualityStrategy: Bool
    var language: AppLanguage = .english
    let onProbe: () -> Void
    let onSelectDirectory: () -> Void
    let onClearDirectory: () -> Void
    var onPaste: (() -> Void)?
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Loc.urlHeading(language))
                .font(.headline)

            HStack(spacing: 6) {
                TextField("https://example.com/video", text: $inputURL, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1 ... 3)
                    .onSubmit { if canProbe { onProbe() } }

                if let onPaste {
                    Button(action: onPaste) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.body)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(Loc.pasteURLHelp(language))
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .onDrop(
                of: [UTType.url.identifier, UTType.plainText.identifier],
                isTargeted: $isDropTargeted,
                perform: handleDrop(providers:)
            )

            Text(Loc.dragHint(language))
                .font(.caption)
                .foregroundStyle(.secondary)

            if showsPlaylistModePicker {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(Loc.playlistMode(language))
                            .font(.subheadline.weight(.semibold))

                        Picker(Loc.playlistMode(language), selection: $playlistConfig.mode) {
                            ForEach(PlaylistMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 280, alignment: .leading)
                    }

                    Text(playlistModeHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if showsPlaylistVideoQualityStrategy {
                        secondaryQualityPicker(
                            label: Loc.videoQuality(language),
                            helpText: Loc.videoQualityHelp(language)
                        ) {
                            Picker(Loc.videoQuality(language), selection: $playlistConfig.videoQualityStrategy) {
                                ForEach(PlaylistVideoQualityStrategy.allCases) { strategy in
                                    Text(strategy.title).tag(strategy)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 280, alignment: .leading)
                        }
                    }

                    if showsPlaylistAudioQualityStrategy {
                        secondaryQualityPicker(
                            label: Loc.audioQuality(language),
                            helpText: Loc.audioQualityHelp(language)
                        ) {
                            Picker(Loc.audioQuality(language), selection: $playlistConfig.audioQualityStrategy) {
                                ForEach(PlaylistAudioQualityStrategy.allCases) { strategy in
                                    Text(strategy.title).tag(strategy)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 280, alignment: .leading)
                        }
                    }

                    if playlistConfig.mode.downloadsWholePlaylist {
                        secondaryQualityPicker(
                            label: Loc.playlistFormats(language),
                            helpText: Loc.playlistFormatsHelp(language)
                        ) {
                            Picker(Loc.playlistFormats(language), selection: $playlistConfig.formatMode) {
                                ForEach(PlaylistFormatMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 280, alignment: .leading)
                        }

                        if playlistConfig.formatMode == .perItemMapping {
                            secondaryTextField(
                                label: Loc.perItemMap(language),
                                placeholder: "1=137+140;2=136+140",
                                text: $playlistConfig.perItemFormatMap,
                                helpText: Loc.perItemMapHelp(language)
                            )
                        }

                        secondaryQualityPicker(
                            label: Loc.playlistSubtitles(language),
                            helpText: Loc.playlistSubtitlesHelp(language)
                        ) {
                            Picker(Loc.playlistSubtitles(language), selection: $playlistConfig.subtitleMode) {
                                ForEach(PlaylistSubtitleMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 280, alignment: .leading)
                        }

                        if playlistConfig.subtitleMode != .none {
                            secondaryTextField(
                                label: Loc.subtitleLanguageLabel(language),
                                placeholder: "en or zh-Hans",
                                text: $playlistConfig.subtitleLanguage,
                                helpText: Loc.subtitleLanguageHelp(language)
                            )
                        }

                        secondaryQualityPicker(
                            label: Loc.playlistSegments(language),
                            helpText: Loc.playlistSegmentsHelp(language)
                        ) {
                            Picker(Loc.playlistSegments(language), selection: $playlistConfig.segmentMode) {
                                ForEach(PlaylistSegmentMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 280, alignment: .leading)
                        }

                        if playlistConfig.segmentMode == .fixedRange {
                            secondaryTextField(
                                label: Loc.timeRange(language),
                                placeholder: "00:30-01:00",
                                text: $playlistConfig.segmentRange,
                                helpText: Loc.timeRangeHelp(language)
                            )
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Label(probeState.localizedStatusLabel(language), systemImage: probeState.symbolName)
                    .foregroundStyle(probeState.tintColor)

                Button(action: onSelectDirectory) {
                    Label(
                        selectedDirectory?.lastPathComponent ?? Loc.chooseFolderHint(language),
                        systemImage: "folder"
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                if selectedDirectory != nil {
                    Button(action: onClearDirectory) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help(Loc.clearFolderHelp(language))
                }

                Spacer(minLength: 0)

                if canShowProbeButton {
                    Button(probeButtonTitle, action: onProbe)
                        .keyboardShortcut(.return)
                        .disabled(!canProbe)
                }
            }
        }
    }

    private var canProbe: Bool {
        !inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && probeState != .loading
            && canShowProbeButton
    }

    private var canShowProbeButton: Bool {
        !showsPlaylistModePicker || playlistConfig.mode == .onlyFirstItem
    }

    private var probeButtonTitle: String {
        showsPlaylistModePicker ? Loc.probeFirstItem(language) : Loc.probeButton(language)
    }

    private var playlistModeHint: String {
        switch playlistConfig.mode {
        case .onlyFirstItem:
            Loc.playlistModeHintFirst(language)
        case .wholePlaylistBestVideo, .wholePlaylistBestAudio:
            Loc.playlistModeHintWhole(language)
        }
    }

    private func secondaryQualityPicker(
        label: String,
        helpText: String,
        @ViewBuilder picker: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)

                picker()
            }

            Text(helpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 20)
    }

    private func secondaryTextField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        helpText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .frame(maxWidth: 280, alignment: .leading)

            Text(helpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 20)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    if let value = extractDroppedString(from: item) {
                        DispatchQueue.main.async {
                            inputURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }
                return true
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    if let value = extractDroppedString(from: item) {
                        DispatchQueue.main.async {
                            inputURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }
                return true
            }
        }

        return false
    }
}

private func extractDroppedString(from item: NSSecureCoding?) -> String? {
    switch item {
    case let url as URL:
        url.absoluteString
    case let string as String:
        string
    case let data as Data:
        String(data: data, encoding: .utf8)
    case let nsString as NSString:
        nsString as String
    default:
        nil
    }
}

private extension ProbeState {
    func localizedStatusLabel(_ l: AppLanguage) -> String {
        switch self {
        case .idle: return Loc.statusIdle(l)
        case .loading: return Loc.statusProbing(l)
        case let .success(info): return Loc.statusReady(info.title, l)
        case let .failure(error):
            if error.recoverySuggestion == AppState.validationErrorMarker {
                return error.message
            }
            return Loc.statusProbeFailed(error.recoverySuggestion, l)
        }
    }

    var statusLabel: String {
        localizedStatusLabel(.english)
    }

    var symbolName: String {
        switch self {
        case .idle: "circle.dotted"
        case .loading: "bolt.horizontal.circle"
        case .success: "checkmark.circle"
        case .failure: "xmark.octagon"
        }
    }

    var tintColor: Color {
        switch self {
        case .idle: .secondary
        case .loading: .orange
        case .success: .green
        case .failure: .red
        }
    }
}
