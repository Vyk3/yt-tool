import SwiftUI
import UniformTypeIdentifiers

struct URLInputView: View {
    @Binding var inputURL: String
    @Binding var playlistMode: PlaylistMode
    @Binding var playlistVideoQualityStrategy: PlaylistVideoQualityStrategy
    @Binding var playlistAudioQualityStrategy: PlaylistAudioQualityStrategy
    @Binding var playlistSubtitleMode: PlaylistSubtitleMode
    @Binding var playlistSubtitleLanguage: String
    @Binding var playlistSegmentMode: PlaylistSegmentMode
    @Binding var playlistSegmentRange: String
    @Binding var playlistFormatMode: PlaylistFormatMode
    @Binding var playlistPerItemFormatMap: String
    let probeState: ProbeState
    let selectedDirectory: URL?
    let showsPlaylistModePicker: Bool
    let showsPlaylistVideoQualityStrategy: Bool
    let showsPlaylistAudioQualityStrategy: Bool
    let onProbe: () -> Void
    let onSelectDirectory: () -> Void
    let onClearDirectory: () -> Void
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("URL")
                .font(.headline)

            TextField("https://example.com/video", text: $inputURL, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1 ... 3)
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
                .onSubmit { if canProbe { onProbe() } }
                .onDrop(
                    of: [UTType.url.identifier, UTType.plainText.identifier],
                    isTargeted: $isDropTargeted,
                    perform: handleDrop(providers:)
                )

            Text("You can also drag a video URL into the field.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if showsPlaylistModePicker {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Playlist mode")
                            .font(.subheadline.weight(.semibold))

                        Picker("Playlist mode", selection: $playlistMode) {
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
                            label: "Video quality",
                            helpText: "Choose whether whole-playlist video downloads favor compatibility or higher quality."
                        ) {
                            Picker("Video quality", selection: $playlistVideoQualityStrategy) {
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
                            label: "Audio quality",
                            helpText: "Choose whether whole-playlist audio downloads favor compatibility or higher quality."
                        ) {
                            Picker("Audio quality", selection: $playlistAudioQualityStrategy) {
                                ForEach(PlaylistAudioQualityStrategy.allCases) { strategy in
                                    Text(strategy.title).tag(strategy)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 280, alignment: .leading)
                        }
                    }

                    if playlistMode.downloadsWholePlaylist {
                        secondaryQualityPicker(
                            label: "Playlist formats",
                            helpText: "Use a single strategy for all items, or map specific items to specific format selectors."
                        ) {
                            Picker("Playlist formats", selection: $playlistFormatMode) {
                                ForEach(PlaylistFormatMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 280, alignment: .leading)
                        }

                        if playlistFormatMode == .perItemMapping {
                            secondaryTextField(
                                label: "Per-item map",
                                placeholder: "1=137+140;2=136+140",
                                text: $playlistPerItemFormatMap,
                                helpText: "Syntax: itemIndex=formatSelector;itemIndex=formatSelector."
                            )
                        }

                        secondaryQualityPicker(
                            label: "Playlist subtitles",
                            helpText: "Apply the same subtitle strategy to each item in the playlist."
                        ) {
                            Picker("Playlist subtitles", selection: $playlistSubtitleMode) {
                                ForEach(PlaylistSubtitleMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 280, alignment: .leading)
                        }

                        if playlistSubtitleMode != .none {
                            secondaryTextField(
                                label: "Subtitle language",
                                placeholder: "en or zh-Hans",
                                text: $playlistSubtitleLanguage,
                                helpText: "Used as --sub-langs for whole-playlist downloads."
                            )
                        }

                        secondaryQualityPicker(
                            label: "Playlist segments",
                            helpText: "Choose whether each item downloads fully or with a fixed time range."
                        ) {
                            Picker("Playlist segments", selection: $playlistSegmentMode) {
                                ForEach(PlaylistSegmentMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 280, alignment: .leading)
                        }

                        if playlistSegmentMode == .fixedRange {
                            secondaryTextField(
                                label: "Time range",
                                placeholder: "00:30-01:00",
                                text: $playlistSegmentRange,
                                helpText: "Passed as --download-sections *<range>."
                            )
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Label(probeState.statusLabel, systemImage: probeState.symbolName)
                    .foregroundStyle(probeState.tintColor)

                Button(action: onSelectDirectory) {
                    Label(
                        selectedDirectory?.lastPathComponent ?? "Choose folder…",
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
                    .help("Clear selected folder")
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
        !showsPlaylistModePicker || playlistMode == .onlyFirstItem
    }

    private var probeButtonTitle: String {
        showsPlaylistModePicker ? "Probe first item" : "Probe"
    }

    private var playlistModeHint: String {
        switch playlistMode {
        case .onlyFirstItem:
            "Probe inspects only the first item, then downloads it like a single video."
        case .wholePlaylistBestVideo, .wholePlaylistBestAudio:
            "Whole playlist downloads every item automatically."
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
    var statusLabel: String {
        switch self {
        case .idle: "Idle"
        case .loading: "Probing…"
        case let .success(info): "Ready: \(info.title)"
        case let .failure(error): error.message
        }
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
