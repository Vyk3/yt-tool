import Combine
import Sparkle

@MainActor
final class AppUpdateController: ObservableObject {
    private let controller: SPUStandardUpdaterController
    private var cancellable: AnyCancellable?
    private var hasStarted = false

    @Published var canCheckForUpdates = false

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: \.canCheckForUpdates, on: self)
    }

    func start(autoCheck: Bool) {
        guard !hasStarted else { return }
        hasStarted = true
        controller.updater.automaticallyChecksForUpdates = autoCheck
        controller.startUpdater()
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    func setAutoCheck(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }
}
