import Sparkle

@MainActor
final class AppUpdateController: ObservableObject {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func start(autoCheck: Bool) {
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
