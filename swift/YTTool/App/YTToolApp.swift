import SwiftUI

@main
struct YTToolApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
                .frame(minWidth: 900, minHeight: 620)
        }
        .windowResizability(.contentSize)
    }
}
