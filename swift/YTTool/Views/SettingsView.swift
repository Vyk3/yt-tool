import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    #if canImport(Sparkle)
        @ObservedObject var appUpdateController: AppUpdateController
    #endif

    var body: some View {
        ScrollView {
            #if canImport(Sparkle)
                SettingsTabView(
                    state: state,
                    pollingManager: state.pollingManager,
                    appUpdateController: appUpdateController
                )
            #else
                SettingsTabView(
                    state: state,
                    pollingManager: state.pollingManager
                )
            #endif
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 380)
    }
}
