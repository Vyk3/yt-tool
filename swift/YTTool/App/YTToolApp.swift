import SwiftUI

@main
struct YTToolApp: App {
    @StateObject private var state = AppState()
    #if canImport(Sparkle)
        @StateObject private var appUpdateController = AppUpdateController()
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
                .frame(minWidth: 900, minHeight: 620)
            #if canImport(Sparkle)
                .onAppear {
                    appUpdateController.start(autoCheck: state.autoCheckForAppUpdates)
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
