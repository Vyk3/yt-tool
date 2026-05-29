import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var state: AppState
    @State private var showingHistory = false
    @State private var showingFileImporter = false

    var body: some View {
        ScrollView {
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
            }
            .padding(24)
        }
        .onAppear { state.requestNotificationPermission() }
        .sheet(isPresented: $showingHistory) {
            HistoryView(store: state.historyStore)
        }
    }

    private var singleModeContent: some View {
        Group {
            URLInputView(
                inputURL: $state.inputURL,
                playlistConfig: $state.playlistConfig,
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
                playlistMode: state.playlistConfig.mode,
                isPlaylistURL: state.isPlaylistInputURL,
                selectedVideo: $state.selectedVideoFormat,
                selectedAudio: $state.selectedAudioFormat,
                selectedSubtitle: $state.selectedSubtitle
            )
            estimatedSizeSummary
            DownloadProgressView(
                downloadState: state.downloadState,
                canDownload: state.canDownload,
                showsNoSelectableFormatsHint: state.hasNoSelectableFormatsAfterProbe,
                isDownloading: state.isDownloading,
                ffmpegWarningMessage: state.ffmpegWarningMessage,
                onDownload: state.download,
                onCancel: state.cancelDownload,
                onReset: state.resetDownload
            )
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var estimatedSizeSummary: some View {
        let total = state.estimatedDownloadSizeBytes(
            video: state.selectedVideoFormat,
            audio: state.selectedAudioFormat
        )
        if let total {
            let parts = [
                state.selectedVideoFormat?.fileSizeBytes.map { "video \(formatBytes($0))" },
                state.selectedAudioFormat?.fileSizeBytes.map { "audio \(formatBytes($0))" },
            ].compactMap { $0 }
            let detail = parts.count > 1 ? "  (\(parts.joined(separator: " + ")))" : ""
            Text("Estimated: \(formatBytes(total))\(detail)")
                .font(.callout)
                .foregroundStyle(.secondary)
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

                Picker("Quality", selection: $state.queueQualityStrategy) {
                    ForEach(QueueQualityStrategy.allCases) { strategy in
                        Text(strategy.title).tag(strategy)
                    }
                }
                .frame(maxWidth: 160)

                Spacer()

                Button {
                    showingFileImporter = true
                } label: {
                    Label("Import", systemImage: "doc.text")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Button {
                    state.importURLsFromClipboard(
                        content: NSPasteboard.general.string(forType: .string)
                    )
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Button("Add to Queue", action: state.addToQueue)
                    .disabled(
                        state.queueInputURLs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || state.selectedOutputDirectory == nil
                    )
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    state.importURLsFromFile(at: url)
                }
            case let .failure(error):
                state.appendLog(
                    scope: .download, level: .error,
                    message: "File import failed: \(error.localizedDescription)"
                )
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("YTTool")
                    .font(.largeTitle.weight(.semibold))
                Text(state.appMode == .single
                    ? "Enter a video URL and press Probe to inspect available formats."
                    : "Paste URLs (one per line) and add them to the download queue.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showingHistory = true
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(.borderless)
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
