import Foundation

@MainActor
final class DownloadQueue: ObservableObject {
    @Published var items: [QueueItem] = []
    @Published var isProcessing = false

    private var processingTask: Task<Void, Never>?
    private var onLog: (AppLogScope, AppLogLevel, String) -> Void = { _, _, _ in }
    private var onItemCompleted: (QueueItem) -> Void = { _ in }

    func addURLs(_ urls: [String], config: QueueItemConfig) {
        let newItems = urls
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { QueueItem(url: $0, config: config) }
        items.append(contentsOf: newItems)
    }

    func removeItem(_ item: QueueItem) {
        if item.status == .active {
            cancelItem(item)
        }
        items.removeAll { $0.id == item.id }
    }

    func moveItem(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    func cancelItem(_ item: QueueItem) {
        guard item.status == .active || item.status == .pending else { return }
        item.status = .cancelled
        if let runner = item.runner {
            Task { try? await runner.cancel() }
        }
    }

    func retryItem(_ item: QueueItem) {
        guard item.status.isTerminal else { return }
        item.status = .pending
        item.downloadProgress = nil
        item.outputURL = nil
        item.error = nil
        item.title = nil
        item.runner = nil
        if !isProcessing {
            resumeProcessing(locator: BundledToolLocator())
        }
    }

    func clearCompleted() {
        items.removeAll { $0.status.isTerminal }
    }

    func startProcessing(
        locator: BundledToolLocator = BundledToolLocator(),
        onLog: @escaping (AppLogScope, AppLogLevel, String) -> Void = { _, _, _ in },
        onItemCompleted: @escaping (QueueItem) -> Void = { _ in }
    ) {
        guard !isProcessing else { return }
        self.onLog = onLog
        self.onItemCompleted = onItemCompleted
        resumeProcessing(locator: locator)
    }

    /// Start the processing loop without overwriting stored callbacks.
    /// Used by `retryItem` to resume processing with the callbacks
    /// already installed by the initial `startProcessing` call.
    private func resumeProcessing(locator: BundledToolLocator) {
        guard !isProcessing else { return }
        didResolveAria2c = false
        isProcessing = true
        processingTask = Task {
            while !Task.isCancelled {
                guard let next = items.first(where: { $0.status == .pending }) else { break }
                await processItem(next, locator: locator)
            }
            isProcessing = false
        }
    }

    func stopProcessing() {
        processingTask?.cancel()
        for item in items where item.status == .active {
            cancelItem(item)
        }
        isProcessing = false
    }

    // MARK: - Private

    /// Cached once per `startProcessing` invocation so we don't spawn `/usr/bin/which` per item.
    private var cachedAria2cPath: String?
    private var didResolveAria2c = false

    private func resolvedAria2cPath() -> String? {
        if !didResolveAria2c {
            cachedAria2cPath = Aria2cLocator().findAria2c()?.path
            didResolveAria2c = true
        }
        return cachedAria2cPath
    }

    private func processItem(_ item: QueueItem, locator: BundledToolLocator) async {
        item.status = .active
        item.runner = ProcessRunner()
        let service = YtDlpDownloadService(locator: locator, runner: item.runner!)

        let aria2cPath: String? = if item.config.downloaderPreference == .aria2c {
            resolvedAria2cPath()
        } else {
            nil
        }
        if item.config.downloaderPreference == .aria2c, aria2cPath == nil {
            onLog(.download, .warning, "[\(truncatedURL(item.url))] aria2c not found; falling back to built-in downloader")
        }

        let effectiveTranscode: AudioTranscodeFormat? =
            item.config.audioTranscodeFormat == .original ? nil : item.config.audioTranscodeFormat

        let isPlaylist = Self.isPurePlaylistURL(item.url)
        if isPlaylist {
            onLog(.download, .info, "[\(truncatedURL(item.url))] Playlist URL detected; downloading all items")
        }
        onLog(.download, .info, "[\(truncatedURL(item.url))] Starting download")

        do {
            for try await event in service.download(
                url: item.url,
                videoFormatId: nil,
                audioFormatId: nil,
                formatSelectorOverride: item.config.qualityStrategy.formatSelector,
                includeNoPlaylistOverride: isPlaylist ? false : nil,
                audioTranscodeFormat: effectiveTranscode,
                cookiesFilePath: item.config.cookiesFilePath,
                extraArguments: item.config.extraArguments,
                outputDirectory: item.config.outputDirectory,
                aria2cPath: aria2cPath,
                onLog: { [weak self] kind, message in
                    Task { @MainActor in
                        self?.onLog(.download, kind.appLogLevel, message)
                    }
                }
            ) {
                switch event {
                case let .progress(p):
                    item.downloadProgress = p
                case let .completed(result):
                    item.outputURL = result.outputURL
                    item.title = result.outputURL.deletingPathExtension().lastPathComponent
                }
            }
            item.status = .completed
            onLog(.download, .success, "[\(item.title ?? truncatedURL(item.url))] Completed")
            onItemCompleted(item)
        } catch is CancellationError {
            if item.status != .cancelled {
                item.status = .cancelled
            }
            onLog(.download, .warning, "[\(truncatedURL(item.url))] Cancelled")
        } catch {
            guard item.status != .cancelled else {
                onLog(.download, .warning, "[\(truncatedURL(item.url))] Cancelled")
                return
            }
            item.status = .failed
            item.error = (error as? AppError) ?? AppError(
                message: "Download failed.",
                recoverySuggestion: error.localizedDescription
            )
            onLog(.download, .error, "[\(truncatedURL(item.url))] Failed: \(error.localizedDescription)")
            onItemCompleted(item)
        }
    }

    private func truncatedURL(_ url: String) -> String {
        url.count > 60 ? String(url.prefix(57)) + "..." : url
    }

    /// Returns `true` only for YouTube pure playlist URLs
    /// (`youtube.com/playlist?list=PLxxx`).
    /// Watch URLs with a `list=` param (e.g. `/watch?v=xxx&list=yyy`) return `false`
    /// so `--no-playlist` keeps extracting just the single video.
    /// Non-YouTube URLs and malformed playlist URLs without `list=` also return `false`.
    private static func isPurePlaylistURL(_ url: String) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isYouTubeURL(trimmed),
              let components = URLComponents(string: trimmed) else {
            return false
        }
        guard components.path == "/playlist" else { return false }
        return components.queryItems?.contains {
            $0.name == "list" && !($0.value ?? "").isEmpty
        } == true
    }
}
