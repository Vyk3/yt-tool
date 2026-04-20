import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var inputURL: String = ""
    @Published var probeState: ProbeState = .idle
    @Published var selectedOutputDirectory: URL?
    @Published var downloadState: DownloadState = .idle
    @Published var userFacingError: AppError?

    private let probeService = YtDlpProbeService()
    private var probeTask: Task<Void, Never>?

    func probe() {
        let url = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        probeTask?.cancel()
        probeState = .loading
        userFacingError = nil

        probeTask = Task {
            do {
                let info = try await probeService.probe(url: url)
                probeState = .success(info)
            } catch let error as AppError {
                probeState = .failure(error)
            } catch {
                probeState = .failure(AppError(
                    message: "Probe failed.",
                    recoverySuggestion: error.localizedDescription
                ))
            }
        }
    }
}
