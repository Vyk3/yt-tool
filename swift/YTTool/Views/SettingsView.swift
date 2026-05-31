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
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .center)
            #else
                SettingsTabView(
                    state: state,
                    pollingManager: state.pollingManager
                )
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .center)
            #endif
        }
        .padding(.horizontal, 24)
        .frame(minWidth: 520, minHeight: 480)
    }
}
