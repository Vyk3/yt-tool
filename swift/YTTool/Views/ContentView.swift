import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var state: AppState
    #if canImport(Sparkle)
        @ObservedObject var appUpdateController: AppUpdateController
    #endif
    @State private var showingHistory = false
    @State private var showingFileImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                modePicker

                tabContent
            }
            .padding(24)
        }
        .transaction { $0.animation = nil }
        .onAppear { state.requestNotificationPermission() }
        .sheet(isPresented: $showingHistory) {
            HistoryView(store: state.historyStore, language: state.language)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch state.appMode {
        case .single:
            singleModeContent

            LogPanelView(entries: state.logs, language: state.language)
                .padding(.top, 8)

        case .queue:
            queueModeContent
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity, alignment: .center)

            LogPanelView(entries: state.logs, language: state.language)
                .padding(.top, 8)

        case .subscriptions:
            SubscriptionsView(
                store: state.subscriptionStore,
                pollingManager: state.pollingManager,
                language: state.language,
                onAddToQueue: { url in
                    state.addSingleURLToQueue(url)
                    state.appMode = .queue
                }
            )
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity, alignment: .center)

        case .settings:
            #if canImport(Sparkle)
                SettingsTabView(
                    state: state,
                    pollingManager: state.pollingManager,
                    appUpdateController: appUpdateController
                )
                .frame(maxWidth: .infinity, alignment: .center)
            #else
                SettingsTabView(
                    state: state,
                    pollingManager: state.pollingManager
                )
                .frame(maxWidth: .infinity, alignment: .center)
            #endif
        }
    }

    private var modePicker: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                let allModes = AppMode.allCases
                ForEach(Array(allModes.enumerated()), id: \.element) { index, mode in
                    let isSelected = state.appMode == mode

                    // Thin divider between two unselected tabs
                    if index > 0 {
                        let prevSelected = state.appMode == allModes[index - 1]
                        if !isSelected && !prevSelected {
                            Rectangle()
                                .fill(Color.primary.opacity(0.15))
                                .frame(width: 1, height: 14)
                        }
                    }

                    Button {
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) {
                            state.appMode = mode
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(Loc.tabLabel(mode, state.language))
                            if mode == .subscriptions && !state.pollingManager.newVideos.isEmpty {
                                Circle()
                                    .fill(isSelected ? Color.white : Color.accentColor)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .frame(width: 120)
                        .padding(.vertical, 5)
                        .background(
                            isSelected
                                ? Color.accentColor
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSelected ? .white : .primary)
                }
            }
            .padding(2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
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
                language: state.language,
                onProbe: state.probe,
                onSelectDirectory: selectOutputDirectory,
                onClearDirectory: { state.selectedOutputDirectory = nil },
                onPaste: {
                    if let text = NSPasteboard.general.string(forType: .string) {
                        state.inputURL = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            )
            FormatPickerView(
                probeState: state.probeState,
                playlistMode: state.playlistConfig.mode,
                isPlaylistURL: state.isPlaylistInputURL,
                language: state.language,
                showTechnicalDetails: state.showTechnicalDetails,
                showAllFormats: state.showAllFormats,
                selectedVideo: $state.selectedVideoFormat,
                selectedAudio: $state.selectedAudioFormat,
                selectedSubtitle: $state.selectedSubtitle
            )
            estimatedSizeSummary
            DownloadProgressView(
                downloadState: state.downloadState,
                canDownload: state.canDownload,
                showsNoSelectableFormatsHint: state.hasNoSelectableFormatsAfterProbe,
                hasOutputFolder: state.selectedOutputDirectory != nil,
                isDownloading: state.isDownloading,
                ffmpegWarningMessage: state.ffmpegWarningMessage,
                language: state.language,
                onDownload: state.download,
                onCancel: state.cancelDownload,
                onReset: state.resetDownload,
                onRetry: state.retryDownload
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
            let vLabel = state.language == .chinese ? "视频" : "video"
            let aLabel = state.language == .chinese ? "音频" : "audio"
            let parts = [
                state.selectedVideoFormat?.fileSizeBytes.map { "\(vLabel) \(formatBytes($0))" },
                state.selectedAudioFormat?.fileSizeBytes.map { "\(aLabel) \(formatBytes($0))" },
            ].compactMap { $0 }
            let detail = parts.count > 1 ? "  (\(parts.joined(separator: " + ")))" : ""
            Text(Loc.estimated(formatBytes(total), detail, state.language))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var queueModeContent: some View {
        Group {
            queueURLInput

            QueueView(
                queue: state.downloadQueue,
                language: state.language,
                onStart: state.startQueue
            )
        }
    }

    private var queueURLInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Loc.urlsPerLine(state.language))
                .font(.headline)

            TextField(
                Loc.queueURLPlaceholder(state.language),
                text: $state.queueInputURLs,
                axis: .vertical
            )
            .font(.body.monospaced())
            .lineLimit(3...6)
            .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Button(action: selectOutputDirectory) {
                    Label(
                        state.selectedOutputDirectory?.lastPathComponent ?? Loc.chooseFolderHint(state.language),
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
                    .help(Loc.clearFolderHelp(state.language))
                }

                Picker(Loc.qualityLabel(state.language), selection: $state.queueQualityStrategy) {
                    ForEach(QueueQualityStrategy.allCases) { strategy in
                        Text(Loc.qualityTitle(strategy, state.language)).tag(strategy)
                    }
                }
                .frame(maxWidth: 160)

                Spacer()

                Button {
                    showingFileImporter = true
                } label: {
                    Label(Loc.importButton(state.language), systemImage: "doc.text")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Button {
                    state.importURLsFromClipboard(
                        content: NSPasteboard.general.string(forType: .string)
                    )
                } label: {
                    Label(Loc.pasteButton(state.language), systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                Button(Loc.addToQueue(state.language), action: state.addToQueue)
                    .disabled(
                        state.queueInputURLs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
            }

            if let error = state.queueError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
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
                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showingHistory = true
            } label: {
                Label(Loc.history(state.language), systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }

    private var headerSubtitle: String {
        Loc.headerSubtitle(state.appMode, state.language)
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
