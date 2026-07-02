import SwiftUI

struct PlaylistFormatEditorView: View {
    @ObservedObject var editorState: PlaylistFormatEditorState
    let playlistURL: String
    let probeService: YtDlpProbeService
    let cookiesFilePath: String?
    let extraOptions: [ParsedExtraOption]
    let language: AppLanguage
    let onConfirm: (String) -> Void
    let onDismiss: () -> Void
    let onLog: @Sendable (ServiceLogKind, String) -> Void

    var body: some View {
        let log = onLog
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()

            content

            Divider()

            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(minWidth: 600, idealWidth: 720, minHeight: 400, idealHeight: 560)
        .onAppear {
            editorState.beginEditing()
            if editorState.entries.isEmpty, !editorState.isLoadingEntries {
                editorState.loadEntries(
                    url: playlistURL,
                    probeService: probeService,
                    cookiesFilePath: cookiesFilePath,
                    extraOptions: extraOptions,
                    onLog: log
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Loc.formatEditorTitle(language))
                    .font(.headline)

                Spacer()

                if !editorState.entries.isEmpty {
                    Text(Loc.formatEditorProbed(editorState.probedCount, editorState.entries.count, language))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if editorState.hasStaleProbes {
                Label(Loc.formatEditorStaleWarning(language), systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let log = onLog
        if editorState.isLoadingEntries {
            VStack {
                Spacer()
                ProgressView(Loc.formatEditorLoading(language))
                Spacer()
            }
        } else if let error = editorState.entriesError {
            VStack {
                Spacer()
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                Spacer()
            }
            .padding()
        } else if editorState.entries.isEmpty {
            VStack {
                Spacer()
                Text(Loc.formatEditorEmpty(language))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            VStack(spacing: 0) {
                selectionBar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(editorState.entries) { entry in
                            PlaylistItemRow(
                                entry: entry,
                                isSelected: editorState.selectedIndices.contains(entry.index),
                                probeState: editorState.itemProbeStates[entry.index] ?? .idle,
                                formatSelection: binding(for: entry.index),
                                language: language,
                                onToggle: { editorState.toggleSelection(entry.index) },
                                onRetry: {
                                    editorState.retryItem(
                                        index: entry.index,
                                        playlistURL: playlistURL,
                                        probeService: probeService,
                                        cookiesFilePath: cookiesFilePath,
                                        extraOptions: extraOptions,
                                        onLog: log
                                    )
                                }
                            )

                            if entry.index != editorState.entries.last?.index {
                                Divider().padding(.leading, 40)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    // MARK: - Selection Bar

    @ViewBuilder
    private var selectionBar: some View {
        let log = onLog
        HStack(spacing: 12) {
            Button(Loc.formatEditorSelectAll(language)) {
                editorState.selectAll()
            }
            .buttonStyle(.borderless)

            Button(Loc.formatEditorDeselectAll(language)) {
                editorState.deselectAll()
            }
            .buttonStyle(.borderless)

            Spacer()

            Button(Loc.formatEditorProbeSelected(language)) {
                editorState.probeSelectedItems(
                    playlistURL: playlistURL,
                    probeService: probeService,
                    cookiesFilePath: cookiesFilePath,
                    extraOptions: extraOptions,
                    onLog: log
                )
            }
            .disabled(editorState.selectedIndices.isEmpty)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()

            Button(Loc.formatEditorCancel(language)) {
                editorState.cancelEditing()
                onDismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button(Loc.formatEditorConfirm(language)) {
                let map = editorState.confirmEditing()
                onConfirm(map)
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(editorState.formatSelections.isEmpty)
        }
    }

    // MARK: - Helpers

    private func binding(for index: Int) -> Binding<PlaylistItemFormatSelection> {
        Binding(
            get: { editorState.formatSelections[index] ?? PlaylistItemFormatSelection() },
            set: { editorState.formatSelections[index] = $0 }
        )
    }
}

// MARK: - Playlist Item Row

private struct PlaylistItemRow: View {
    let entry: PlaylistEntry
    let isSelected: Bool
    let probeState: PlaylistItemProbeState
    @Binding var formatSelection: PlaylistItemFormatSelection
    let language: AppLanguage
    let onToggle: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle(isOn: Binding(get: { isSelected }, set: { _ in onToggle() })) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(entry.index).")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)

                    Text(entry.title)
                        .font(.callout)
                        .lineLimit(2)

                    Spacer()

                    Text(entry.formattedDuration)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                formatArea
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var formatArea: some View {
        switch probeState {
        case .idle:
            EmptyView()

        case .loading:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(Loc.formatEditorProbing(language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 32)

        case let .success(info):
            formatPickers(info: info)
                .padding(.leading, 32)

        case let .failure(message):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Button(Loc.formatEditorRetry(language), action: onRetry)
                        .buttonStyle(.borderless)
                        .font(.caption)

                    TextField(Loc.formatEditorManualInput(language), text: $formatSelection.manualInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(maxWidth: 200)
                }
            }
            .padding(.leading, 32)
        }
    }

    private func formatPickers(info: MediaInfo) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Loc.formatEditorVideo(language))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Picker(Loc.formatEditorVideo(language), selection: $formatSelection.videoFormatId) {
                    Text(Loc.formatEditorAutoFormat(language)).tag(nil as String?)
                    ForEach(filterVideoFormats(info.videoFormats)) { fmt in
                        Text(videoLabel(fmt)).tag(fmt.id as String?)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(Loc.formatEditorAudio(language))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Picker(Loc.formatEditorAudio(language), selection: $formatSelection.audioFormatId) {
                    Text(Loc.formatEditorAutoFormat(language)).tag(nil as String?)
                    ForEach(filterAudioFormats(info.audioFormats)) { fmt in
                        Text(audioLabel(fmt)).tag(fmt.id as String?)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
            }
        }
    }

    private func videoLabel(_ fmt: VideoFormat) -> String {
        "\(fmt.resolution) · \(fmt.friendlyCodec)"
    }

    private func audioLabel(_ fmt: AudioFormat) -> String {
        "\(fmt.friendlyCodec) · \(fmt.formattedBitrate)"
    }
}
