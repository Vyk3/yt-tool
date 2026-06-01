import SwiftUI

@main
struct YTToolApp: App {
    @StateObject private var state = AppState()
    #if canImport(Sparkle)
        @StateObject private var appUpdateController = AppUpdateController()
    #endif

    init() {
        // Set AppleLanguages BEFORE any framework (Sparkle) resolves bundle localizations.
        // Must happen before @StateObject lazy init, so frameworks see the correct language.
        if let raw = UserDefaults.standard.string(forKey: "appLanguage"),
           let lang = AppLanguage(rawValue: raw)
        {
            UserDefaults.standard.set([lang.rawValue], forKey: "AppleLanguages")
        }
    }

    var body: some Scene {
        WindowGroup {
            #if canImport(Sparkle)
                ContentView(state: state, appUpdateController: appUpdateController)
                    .frame(minWidth: 760, minHeight: 620)
                    .onAppear {
                        appUpdateController.start(autoCheck: state.autoCheckForAppUpdates)
                        state.pollingManager.startPolling()
                    }
            #else
                ContentView(state: state)
                    .frame(minWidth: 760, minHeight: 620)
                    .onAppear {
                        state.pollingManager.startPolling()
                    }
            #endif
        }
        .defaultSize(width: 800, height: 640)
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
