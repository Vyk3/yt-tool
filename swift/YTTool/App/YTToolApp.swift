import SwiftUI

@main
struct YTToolApp: App {
    @StateObject private var state = AppState()
    #if canImport(Sparkle)
        @StateObject private var appUpdateController = AppUpdateController()
    #endif

    var body: some Scene {
        WindowGroup {
            #if canImport(Sparkle)
                ContentView(state: state, appUpdateController: appUpdateController)
                    .frame(minWidth: 900, minHeight: 620)
                    .onAppear {
                        appUpdateController.start(autoCheck: state.autoCheckForAppUpdates)
                        state.pollingManager.startPolling()
                    }
            #else
                ContentView(state: state)
                    .frame(minWidth: 900, minHeight: 620)
                    .onAppear {
                        state.pollingManager.startPolling()
                    }
            #endif
        }
        .windowResizability(.automatic)

        Settings {
            #if canImport(Sparkle)
                SettingsView(state: state, appUpdateController: appUpdateController)
            #else
                SettingsView(state: state)
            #endif
        }
    }
}
