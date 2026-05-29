import SwiftUI

/// In-app Settings tab that consolidates app-wide configuration.
/// Per-download settings (audio transcode) stay inline in the download area.
struct SettingsTabView: View {
    @ObservedObject var state: AppState
    @ObservedObject var pollingManager: SubscriptionPollingManager
    #if canImport(Sparkle)
        @ObservedObject var appUpdateController: AppUpdateController
    #endif

    private let repoURL = URL(string: "https://github.com/Vyk3/yt-tool")!
    private let releaseURL = URL(string: "https://github.com/Vyk3/yt-tool/releases")!

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            downloadEngineSection
            Divider()
            cookiesSection
            Divider()
            extraArgsSection
            Divider()
            subscriptionPollSection
            Divider()
            ytDlpUpdateSection
            #if canImport(Sparkle)
                Divider()
                appUpdateSection
            #endif
            Divider()
            aboutSection
            Spacer(minLength: 0)
        }
    }

    // MARK: - Download engine

    private var downloadEngineSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Download Engine")
                .font(.headline)

            Picker("Engine", selection: $state.downloaderPreference) {
                ForEach(DownloaderPreference.allCases) { pref in
                    Text(pref.label).tag(pref)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 220, alignment: .leading)
            .disabled(!state.aria2cAvailable && state.downloaderPreference == .native)

            if !state.aria2cAvailable {
                Text("aria2c not found. Install via: brew install aria2")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Cookies

    private var cookiesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cookies File Path")
                .font(.headline)
            TextField("/path/to/cookies.txt", text: $state.cookiesFilePath)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            Text("Optional. The path must exist and be readable.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Extra args

    private var extraArgsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Extra yt-dlp Arguments")
                .font(.headline)
            TextField("--download-sections \"*00:30-01:00\"", text: $state.extraYtDlpArguments)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
            Text("Optional. Passed through after validation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Subscription polling

    private var subscriptionPollSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Subscription Check Interval")
                .font(.headline)

            Picker("Interval", selection: Binding(
                get: { pollingManager.pollInterval },
                set: { pollingManager.pollInterval = $0 }
            )) {
                Text("15 minutes").tag(TimeInterval(15 * 60))
                Text("30 minutes").tag(TimeInterval(30 * 60))
                Text("1 hour").tag(TimeInterval(60 * 60))
                Text("2 hours").tag(TimeInterval(120 * 60))
            }
            .labelsHidden()
            .frame(maxWidth: 220, alignment: .leading)

            Text("How often to check subscribed channels for new uploads.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - yt-dlp update

    private var ytDlpUpdateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("yt-dlp Updates")
                .font(.headline)
            UpdateView(state: state)
        }
    }

    // MARK: - App updates

    #if canImport(Sparkle)
        private var appUpdateSection: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("App Updates")
                    .font(.headline)

                Toggle("Check for app updates automatically", isOn: $state.autoCheckForAppUpdates)
                    .onChange(of: state.autoCheckForAppUpdates) { newValue in
                        appUpdateController.setAutoCheck(newValue)
                    }

                Button("Check for App Updates", action: appUpdateController.checkForUpdates)
                    .disabled(!appUpdateController.canCheckForUpdates)
            }
        }
    #endif

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("About")
                .font(.headline)
            LabeledContent("App version", value: appVersion)
            LabeledContent("Build", value: appBuild)
            HStack(spacing: 12) {
                Link("Repository", destination: repoURL)
                Link("Releases", destination: releaseURL)
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }
}
