import Foundation

enum PlaylistItemProbeState: Equatable {
    case idle
    case loading
    case success(MediaInfo)
    case failure(String)
}

struct PlaylistItemFormatSelection: Equatable {
    var videoFormatId: String?
    var audioFormatId: String?
    var manualInput: String = ""

    var effectiveSelector: String? {
        if !manualInput.isEmpty { return manualInput }
        guard let vid = videoFormatId else { return audioFormatId }
        guard let aid = audioFormatId else { return vid }
        return "\(vid)+\(aid)"
    }
}

@MainActor
final class PlaylistFormatEditorState: ObservableObject {
    @Published var entries: [PlaylistEntry] = []
    @Published var selectedIndices: Set<Int> = []
    @Published var itemProbeStates: [Int: PlaylistItemProbeState] = [:]
    @Published var formatSelections: [Int: PlaylistItemFormatSelection] = [:]
    @Published var isLoadingEntries = false
    @Published var entriesError: String?
    @Published var probeTimestamps: [Int: Date] = [:]

    private var confirmedSelections: [Int: PlaylistItemFormatSelection] = [:]
    private var batchTask: Task<Void, Never>?
    private var batchProbeIndices: Set<Int> = []
    private var probeTasks: [Int: Task<Void, Never>] = [:]
    private var loadEntriesTask: Task<Void, Never>?
    private var cachedURL: String?

    private static let maxConcurrentProbes = 3

    var probedCount: Int {
        itemProbeStates.values.filter {
            if case .success = $0 { return true }
            return false
        }.count
    }

    var hasStaleProbes: Bool {
        let threshold: TimeInterval = 30 * 60
        let now = Date()
        return probeTimestamps.values.contains { now.timeIntervalSince($0) > threshold }
    }

    // MARK: - Entry Loading

    func loadEntries(
        url: String,
        probeService: YtDlpProbeService,
        cookiesFilePath: String?,
        extraOptions: [ParsedExtraOption],
        onLog: @escaping @Sendable (ServiceLogKind, String) -> Void
    ) {
        loadEntriesTask?.cancel()
        isLoadingEntries = true
        entriesError = nil

        loadEntriesTask = Task {
            do {
                let loaded = try await probeService.probePlaylist(
                    url: url,
                    cookiesFilePath: cookiesFilePath,
                    extraOptions: extraOptions,
                    onLog: onLog
                )
                guard !Task.isCancelled else { return }
                entries = loaded
                selectedIndices = Set(loaded.map(\.index))
                cachedURL = url
                isLoadingEntries = false
            } catch {
                guard !Task.isCancelled else { return }
                entriesError = error.localizedDescription
                isLoadingEntries = false
            }
        }
    }

    // MARK: - Batch Probing

    func probeSelectedItems(
        playlistURL: String,
        probeService: YtDlpProbeService,
        cookiesFilePath: String?,
        extraOptions: [ParsedExtraOption],
        onLog: @escaping @Sendable (ServiceLogKind, String) -> Void
    ) {
        let indices = selectedIndices.sorted().filter { idx in
            if case .success = itemProbeStates[idx] { return false }
            if case .loading = itemProbeStates[idx] { return false }
            return true
        }
        guard !indices.isEmpty else { return }

        for idx in indices {
            probeTasks[idx]?.cancel()
            probeTasks[idx] = nil
        }

        batchTask?.cancel()
        for idx in batchProbeIndices where itemProbeStates[idx] == .loading {
            itemProbeStates[idx] = .idle
        }
        batchProbeIndices = Set(indices)

        for idx in indices {
            itemProbeStates[idx] = .loading
        }
        batchTask = Task {
            await withTaskGroup(of: Void.self) { group in
                var running = 0
                var pending = indices.makeIterator()

                func addNext() -> Bool {
                    guard let idx = pending.next() else { return false }
                    group.addTask { [weak self] in
                        await self?.performItemProbe(
                            index: idx,
                            playlistURL: playlistURL,
                            probeService: probeService,
                            cookiesFilePath: cookiesFilePath,
                            extraOptions: extraOptions,
                            onLog: onLog
                        )
                    }
                    return true
                }

                for _ in 0 ..< Self.maxConcurrentProbes {
                    guard addNext() else { break }
                    running += 1
                }

                for await _ in group {
                    running -= 1
                    if addNext() {
                        running += 1
                    }
                    if running == 0 { break }
                }
            }
        }
    }

    func retryItem(
        index: Int,
        playlistURL: String,
        probeService: YtDlpProbeService,
        cookiesFilePath: String?,
        extraOptions: [ParsedExtraOption],
        onLog: @escaping @Sendable (ServiceLogKind, String) -> Void
    ) {
        probeTasks[index]?.cancel()
        itemProbeStates[index] = .loading
        probeTasks[index] = Task {
            await performItemProbe(
                index: index,
                playlistURL: playlistURL,
                probeService: probeService,
                cookiesFilePath: cookiesFilePath,
                extraOptions: extraOptions,
                onLog: onLog
            )
        }
    }

    private func performItemProbe(
        index: Int,
        playlistURL: String,
        probeService: YtDlpProbeService,
        cookiesFilePath: String?,
        extraOptions: [ParsedExtraOption],
        onLog: @escaping @Sendable (ServiceLogKind, String) -> Void
    ) async {
        do {
            let info = try await probeService.probePlaylistItem(
                playlistURL: playlistURL,
                itemIndex: index,
                cookiesFilePath: cookiesFilePath,
                extraOptions: extraOptions,
                onLog: onLog
            )
            guard !Task.isCancelled else { return }
            itemProbeStates[index] = .success(info)
            probeTimestamps[index] = Date()
            if formatSelections[index] == nil {
                var selection = PlaylistItemFormatSelection()
                if let firstVideo = filterVideoFormats(info.videoFormats).first {
                    selection.videoFormatId = firstVideo.id
                }
                if let firstAudio = filterAudioFormats(info.audioFormats).first {
                    selection.audioFormatId = firstAudio.id
                }
                formatSelections[index] = selection
            }
        } catch {
            guard !Task.isCancelled else { return }
            itemProbeStates[index] = .failure(error.localizedDescription)
        }
    }

    // MARK: - Draft / Confirm Lifecycle

    func beginEditing() {
        formatSelections = confirmedSelections
    }

    func confirmEditing() -> String {
        confirmedSelections = formatSelections
        return buildPerItemFormatMap()
    }

    func cancelEditing() {
        cancelAllProbes()
        formatSelections = confirmedSelections
    }

    func buildPerItemFormatMap() -> String {
        formatSelections
            .sorted(by: { $0.key < $1.key })
            .map { idx, sel in
                let selector = sel.effectiveSelector ?? "bestvideo+bestaudio/best"
                return "\(idx)=\(selector)"
            }
            .joined(separator: ";")
    }

    func restoreFromConfig(overridesString: String) {
        formatSelections = [:]
        confirmedSelections = [:]
        guard !overridesString.isEmpty else { return }
        let pairs = overridesString.split(separator: ";", omittingEmptySubsequences: true)
        for pair in pairs {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, let index = Int(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)) else {
                continue
            }
            let selector = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            var sel = PlaylistItemFormatSelection()
            if selector.contains("/") {
                sel.manualInput = selector
            } else {
                let components = selector.split(separator: "+", maxSplits: 1).map(String.init)
                if components.count == 2 {
                    sel.videoFormatId = components[0]
                    sel.audioFormatId = components[1]
                } else {
                    sel.manualInput = selector
                }
            }
            formatSelections[index] = sel
            confirmedSelections[index] = sel
        }
    }

    // MARK: - Cache & Lifecycle

    func invalidateCacheIfNeeded(url: String) {
        guard url != cachedURL else { return }
        loadEntriesTask?.cancel()
        loadEntriesTask = nil
        isLoadingEntries = false
        entries = []
        selectedIndices = []
        itemProbeStates = [:]
        formatSelections = [:]
        confirmedSelections = [:]
        probeTimestamps = [:]
        entriesError = nil
        cachedURL = nil
        cancelAllProbes()
    }

    func cancelAll() {
        loadEntriesTask?.cancel()
        loadEntriesTask = nil
        cancelAllProbes()
    }

    private func cancelAllProbes() {
        batchTask?.cancel()
        batchTask = nil
        batchProbeIndices.removeAll()
        for (_, task) in probeTasks {
            task.cancel()
        }
        probeTasks.removeAll()
        for (idx, state) in itemProbeStates where state == .loading {
            itemProbeStates[idx] = .idle
        }
    }

    // MARK: - Selection

    func selectAll() {
        selectedIndices = Set(entries.map(\.index))
    }

    func deselectAll() {
        selectedIndices = []
    }

    func toggleSelection(_ index: Int) {
        if selectedIndices.contains(index) {
            selectedIndices.remove(index)
        } else {
            selectedIndices.insert(index)
        }
    }
}
