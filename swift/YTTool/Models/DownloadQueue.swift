import Foundation

@MainActor
final class DownloadQueue: ObservableObject {
    @Published var items: [QueueItem] = []
    @Published var isProcessing = false

    private var processingTask: Task<Void, Never>?
    private var onLog: ((AppLogScope, AppLogLevel, String) -> Void)?

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
            startProcessing(locator: BundledToolLocator())
        }
    }

    func clearCompleted() {
        items.removeAll { $0.status.isTerminal }
    }

    func startProcessing(
        locator: BundledToolLocator = BundledToolLocator(),
        onLog: ((AppLogScope, AppLogLevel, String) -> Void)? = nil
    ) {
        guard !isProcessing else { return }
        self.onLog = onLog
        isProcessing = true
        processingTask = Task {
            while !Task.isCancelled {
                guard let next = items.first(where: { $0.status == .pending }) else { break }
                await processItem(next, locator: locator)
            }
            isProcessing = false
            self.onLog = nil
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

    private func processItem(_ item: QueueItem, locator: BundledToolLocator) async {
        item.status = .active
        item.runner = ProcessRunner()
        let service = YtDlpDownloadService(locator: locator, runner: item.runner!)

        let aria2cPath: String? = if item.config.downloaderPreference == .aria2c {
            Aria2cLocator().findAria2c()?.path
        } else {
            nil
        }
        if item.config.downloaderPreference == .aria2c, aria2cPath == nil {
            onLog?(.download, .warning, "[\(truncatedURL(item.url))] aria2c not found; falling back to built-in downloader")
        }

        let effectiveTranscode: AudioTranscodeFormat? =
            item.config.audioTranscodeFormat == .original ? nil : item.config.audioTranscodeFormat

        onLog?(.download, .info, "[\(truncatedURL(item.url))] Starting download")

        do {
            for try await event in service.download(
                url: item.url,
                videoFormatId: nil,
                audioFormatId: nil,
                audioTranscodeFormat: effectiveTranscode,
                cookiesFilePath: item.config.cookiesFilePath,
                extraArguments: item.config.extraArguments,
                outputDirectory: item.config.outputDirectory,
                aria2cPath: aria2cPath,
                onLog: { [weak self] kind, message in
                    let level: AppLogLevel = switch kind {
                    case .command, .lifecycle, .stdout: .info
                    case .stderr: .warning
                    }
                    Task { @MainActor in
                        self?.onLog?(.download, level, message)
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
            onLog?(.download, .success, "[\(item.title ?? truncatedURL(item.url))] Completed")
        } catch is CancellationError {
            if item.status != .cancelled {
                item.status = .cancelled
            }
            onLog?(.download, .warning, "[\(truncatedURL(item.url))] Cancelled")
        } catch {
            item.status = .failed
            item.error = (error as? AppError) ?? AppError(
                message: "Download failed.",
                recoverySuggestion: error.localizedDescription
            )
            onLog?(.download, .error, "[\(truncatedURL(item.url))] Failed: \(error.localizedDescription)")
        }
    }

    private func truncatedURL(_ url: String) -> String {
        url.count > 60 ? String(url.prefix(57)) + "..." : url
    }
}
