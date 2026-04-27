import SwiftUI

struct ContentView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            URLInputView(
                inputURL: $state.inputURL,
                playlistMode: $state.playlistMode,
                playlistVideoQualityStrategy: $state.playlistVideoQualityStrategy,
                playlistAudioQualityStrategy: $state.playlistAudioQualityStrategy,
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
                selectedAudio: $state.selectedAudioFormat
            )
            DownloadProgressView(
                downloadState: state.downloadState,
                canDownload: state.canDownload,
                isDownloading: state.isDownloading,
                ffmpegWarningMessage: state.ffmpegWarningMessage,
                onDownload: state.download,
                onCancel: state.cancelDownload
            )
            .padding(.top, 4)

            LogPanelView(entries: state.logs)
                .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .padding(24)
        .onAppear { state.requestNotificationPermission() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YTTool")
                .font(.largeTitle.weight(.semibold))
            Text("Enter a video URL and press Probe to inspect available formats.")
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
