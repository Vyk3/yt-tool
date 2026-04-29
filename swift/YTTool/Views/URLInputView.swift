import SwiftUI
import UniformTypeIdentifiers

struct URLInputView: View {
    @Binding var inputURL: String
    @Binding var playlistMode: PlaylistMode
    @Binding var playlistVideoQualityStrategy: PlaylistVideoQualityStrategy
    @Binding var playlistAudioQualityStrategy: PlaylistAudioQualityStrategy
    @Binding var audioTranscodeFormat: AudioTranscodeFormat
    @Binding var cookiesFilePath: String
    @Binding var extraYtDlpArguments: String
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
                }
            }

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
            return "Probe inspects only the first item, then downloads it like a single video."
        case .wholePlaylistBestVideo, .wholePlaylistBestAudio:
            return "Whole playlist downloads every item automatically."
        }
    }

    @ViewBuilder
    private func secondaryQualityPicker<PickerContent: View>(
        label: String,
        helpText: String,
        @ViewBuilder picker: () -> PickerContent
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
        return url.absoluteString
    case let string as String:
        return string
    case let data as Data:
        return String(data: data, encoding: .utf8)
    case let nsString as NSString:
        return nsString as String
    default:
        return nil
    }
}

private extension ProbeState {
    var statusLabel: String {
        switch self {
        case .idle: return "Idle"
        case .loading: return "Probing…"
        case .success(let info): return "Ready: \(info.title)"
        case .failure(let error): return error.message
        }
    }

    var symbolName: String {
        switch self {
        case .idle: return "circle.dotted"
        case .loading: return "bolt.horizontal.circle"
        case .success: return "checkmark.circle"
        case .failure: return "xmark.octagon"
        }
    }

    var tintColor: Color {
        switch self {
        case .idle: return .secondary
        case .loading: return .orange
        case .success: return .green
        case .failure: return .red
        }
    }
}
