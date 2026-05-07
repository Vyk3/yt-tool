import SwiftUI

struct ContentView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            Picker("Mode", selection: $state.appMode) {
                ForEach(AppMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)

            if state.appMode == .single {
                singleModeContent
            } else {
                queueModeContent
            }

            AdvancedOptionsView(
                audioTranscodeFormat: $state.audioTranscodeFormat,
                cookiesFilePath: $state.cookiesFilePath,
                extraYtDlpArguments: $state.extraYtDlpArguments,
                downloaderPreference: $state.downloaderPreference,
                aria2cAvailable: state.aria2cAvailable
            )

            LogPanelView(entries: state.logs)
                .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .padding(24)
        .onAppear { state.requestNotificationPermission() }
    }

    private var singleModeContent: some View {
        Group {
            URLInputView(
                inputURL: $state.inputURL,
                playlistMode: $state.playlistMode,
                playlistVideoQualityStrategy: $state.playlistVideoQualityStrategy,
                playlistAudioQualityStrategy: $state.playlistAudioQualityStrategy,
                playlistSubtitleMode: $state.playlistSubtitleMode,
                playlistSubtitleLanguage: $state.playlistSubtitleLanguage,
                playlistSegmentMode: $state.playlistSegmentMode,
                playlistSegmentRange: $state.playlistSegmentRange,
                playlistFormatMode: $state.playlistFormatMode,
                playlistPerItemFormatMap: $state.playlistPerItemFormatMap,
                probeState: state.probeState,
                selectedDirectory: state.selectedOutputDirectory,
                showsPlaylistModePicker: state.isPlaylistInputURL,
                showsPlaylistVideoQualityStrategy: state.showsPlaylistVideoQualityStrategy,
                showsPlaylistAudioQualityStrategy: state.showsPlaylistAudioQualityStrategy,
                onProbe: state.probe,
                onSelectDirectory: selectOutputDirectory,
                onClearDirectory: { state.selectedOutputDirectory = nil }
            )
            FormatPickerView(
                probeState: state.probeState,
                playlistMode: state.playlistMode,
                isPlaylistURL: state.isPlaylistInputURL,
                selectedVideo: $state.selectedVideoFormat,
                selectedAudio: $state.selectedAudioFormat,
                selectedSubtitle: $state.selectedSubtitle
            )
            DownloadProgressView(
                downloadState: state.downloadState,
                canDownload: state.canDownload,
                showsNoSelectableFormatsHint: state.hasNoSelectableFormatsAfterProbe,
                isDownloading: state.isDownloading,
                ffmpegWarningMessage: state.ffmpegWarningMessage,
                onDownload: state.download,
                onCancel: state.cancelDownload
            )
            .padding(.top, 4)
        }
    }

    private var queueModeContent: some View {
        Group {
            queueURLInput

            QueueView(
                queue: state.downloadQueue,
                onStart: state.startQueue
            )
        }
    }

    private var queueURLInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("URLs (one per line)")
                .font(.headline)

            TextEditor(text: $state.queueInputURLs)
                .font(.body.monospaced())
                .frame(minHeight: 60, maxHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            HStack(spacing: 12) {
                Button(action: selectOutputDirectory) {
                    Label(
                        state.selectedOutputDirectory?.lastPathComponent ?? "Choose folder...",
                        systemImage: "folder"
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                if state.selectedOutputDirectory != nil {
                    Button(action: { state.selectedOutputDirectory = nil }) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Clear selected folder")
                }

                Spacer()

                Button("Add to Queue", action: state.addToQueue)
                    .disabled(
                        state.queueInputURLs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || state.selectedOutputDirectory == nil
                    )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YTTool")
                .font(.largeTitle.weight(.semibold))
            Text(state.appMode == .single
                ? "Enter a video URL and press Probe to inspect available formats."
                : "Paste URLs (one per line) and add them to the download queue.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        if panel.runModal() == .OK {
            state.selectedOutputDirectory = panel.url
        }
    }
}
