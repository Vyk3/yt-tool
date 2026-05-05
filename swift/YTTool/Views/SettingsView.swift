import SwiftUI

struct SettingsView: View {
    private let repoURL = URL(string: "https://github.com/Vyk3/yt-tool")!
    private let releaseURL = URL(string: "https://github.com/Vyk3/yt-tool/releases")!

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("About YTTool")
                .font(.title2.weight(.semibold))

            LabeledContent("App version", value: appVersion)
            LabeledContent("Build", value: appBuild)

            HStack(spacing: 12) {
                Link("Open official repository", destination: repoURL)
                Link("Check latest release", destination: releaseURL)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 220)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }
}
