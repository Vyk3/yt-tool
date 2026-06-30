import SwiftUI

/// In-app Settings tab — compact 3-column layout:
/// section label (left) | setting name (center) | control (right-aligned).
struct SettingsTabView: View {
    @ObservedObject var state: AppState
    @ObservedObject var pollingManager: SubscriptionPollingManager
    #if canImport(Sparkle)
        @ObservedObject var appUpdateController: AppUpdateController
    #endif

    private let repoURL = URL(string: "https://github.com/Vyk3/yt-tool")!

    @State private var showsCookiesGuide = false
    @State private var showsPrivacyInfo = false
    @State private var showsClearLocalDataConfirmation = false

    private var lang: AppLanguage {
        state.language
    }

    /// Section label column width — adaptive to avoid wrapping in English.
    private var sectionColumnWidth: CGFloat {
        lang == .chinese ? 44 : 90
    }

    /// Title column width — adaptive: 135pt for Chinese (longest: "启动时检查 yt-dlp 更新"),
    /// 170pt for English (longest: "Extra yt-dlp arguments").
    private var titleColumnWidth: CGFloat {
        lang == .chinese ? 135 : 170
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Display / Language + Appearance ───────────────────────
            settingsRow(
                section: Loc.sectionLanguage(lang),
                title: Loc.languageLabel(lang)
            ) {
                Picker(Loc.languageLabel(lang), selection: $state.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden()
            }

            settingsRow(title: Loc.appearanceLabel(lang)) {
                Picker(Loc.appearanceLabel(lang), selection: $state.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(Loc.appearanceTitle(appearance, lang)).tag(appearance)
                    }
                }
                .labelsHidden()
            }

            settingsRow(
                title: Loc.technicalDetails(lang),
                help: Loc.technicalDetailsHelp(lang)
            ) {
                Toggle("", isOn: $state.showTechnicalDetails)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            settingsRow(
                title: Loc.showAllFormats(lang),
                help: Loc.showAllFormatsHelp(lang)
            ) {
                Toggle("", isOn: $state.showAllFormats)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            sectionDivider()

            // ── Download ────────────────────────────────────────────
            settingsRow(
                section: Loc.sectionDownload(lang),
                title: Loc.downloadEngine(lang),
                status: state.aria2cAvailable ? nil : Loc.aria2cNotFound(lang)
            ) {
                Picker(Loc.downloadEngine(lang), selection: $state.downloaderPreference) {
                    ForEach(DownloaderPreference.allCases) { pref in
                        Text(pref.label).tag(pref)
                    }
                }
                .labelsHidden()
            }

            settingsRow(title: Loc.audioTranscode(lang)) {
                Picker(Loc.audioTranscode(lang), selection: $state.audioTranscodeFormat) {
                    ForEach(AudioTranscodeFormat.allCases) { format in
                        Text(Loc.audioTranscodeLocalized(format, lang)).tag(format)
                    }
                }
                .labelsHidden()
            }

            settingsRow(
                title: Loc.cookiesFile(lang),
                help: Loc.cookiesDescription(lang)
            ) {
                HStack(spacing: 6) {
                    Text(Loc.cookiesGuideLink(lang))
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .onTapGesture { showsCookiesGuide.toggle() }
                        .popover(isPresented: $showsCookiesGuide) {
                            cookiesGuidePopover
                        }

                    TextField("/path/to/cookies.txt", text: $state.cookiesFilePath)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                }
            }

            settingsRow(
                title: Loc.extraArgs(lang),
                help: Loc.extraArgsDescription(lang)
            ) {
                TextField("e.g. --download-sections", text: $state.extraYtDlpArguments)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
            }

            sectionDivider()

            // ── Subscriptions ───────────────────────────────────────
            settingsRow(
                section: Loc.sectionSubscriptions(lang),
                title: Loc.checkInterval(lang),
                help: Loc.checkIntervalDescription(lang)
            ) {
                Picker(Loc.checkInterval(lang), selection: Binding(
                    get: { pollingManager.pollInterval },
                    set: { pollingManager.pollInterval = $0 }
                )) {
                    Text(Loc.interval15min(lang)).tag(TimeInterval(15 * 60))
                    Text(Loc.interval30min(lang)).tag(TimeInterval(30 * 60))
                    Text(Loc.interval1hour(lang)).tag(TimeInterval(60 * 60))
                    Text(Loc.interval2hours(lang)).tag(TimeInterval(120 * 60))
                }
                .labelsHidden()
            }

            sectionDivider()

            // ── Updates (yt-dlp + App) ──────────────────────────────
            updatesSection

            sectionDivider()

            // ── About ──────────────────────────────────────────────
            settingsRow(
                section: Loc.sectionPrivacy(lang),
                title: Loc.clearLocalData(lang),
                help: Loc.clearLocalDataHelp(lang),
                status: state.localDataStatusMessage
            ) {
                Button(Loc.clearLocalData(lang), role: .destructive) {
                    showsClearLocalDataConfirmation = true
                }
                .disabled(state.isDownloadOrQueueActive)
            }

            sectionDivider()

            // ── About ──────────────────────────────────────────────
            aboutSection

            Spacer(minLength: 0)
        }
        .frame(maxWidth: lang == .chinese ? 500 : 560)
        .alert(Loc.clearLocalDataConfirmTitle(lang), isPresented: $showsClearLocalDataConfirmation) {
            Button(Loc.cancel(lang), role: .cancel) {}
            Button(Loc.clearLocalData(lang), role: .destructive) {
                do {
                    try state.clearLocalData()
                } catch {
                    state.appendLog(scope: .app, level: .error, message: error.localizedDescription)
                }
            }
        } message: {
            Text(Loc.clearLocalDataConfirmMessage(lang))
        }
    }

    // MARK: - Updates section (yt-dlp + App combined)

    @ViewBuilder
    private var updatesSection: some View {
        // yt-dlp dependency row — description inline, version on right
        settingsRow(
            section: Loc.sectionUpdates(lang),
            title: Loc.ytDlpDependency(lang),
            help: Loc.ytDlpDescription(lang)
        ) {
            if let version = state.currentYtDlpVersion {
                Text("\(version) (\(state.ytDlpSource))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }

        settingsRow(title: Loc.channelLabel(lang)) {
            Picker(Loc.channelLabel(lang), selection: $state.updateChannel) {
                ForEach(UpdateChannel.allCases) { channel in
                    Text(channel.label).tag(channel)
                }
            }
            .labelsHidden()
        }

        settingsRow(title: Loc.autoCheckYtDlp(lang)) {
            Toggle("", isOn: $state.autoCheckForUpdates)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }

        // yt-dlp update status
        ytDlpStatusRow

        // Thin divider between yt-dlp and app updates
        Divider()
            .padding(.vertical, 2)
            .padding(.leading, sectionColumnWidth + 12)
            .padding(.horizontal, 4)

        // App updates — toggle only, no redundant button text
        #if canImport(Sparkle)
            settingsRow(title: Loc.automaticChecks(lang)) {
                Toggle("", isOn: $state.autoCheckForAppUpdates)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: state.autoCheckForAppUpdates) { _, newValue in
                        appUpdateController.setAutoCheck(newValue)
                    }
            }

            // Manual check action — right-aligned in control column
            HStack(spacing: 12) {
                Color.clear.frame(width: sectionColumnWidth)
                Color.clear.frame(width: titleColumnWidth)
                Spacer(minLength: 0)
                Button(Loc.checkForAppUpdates(lang), action: appUpdateController.checkForUpdates)
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .disabled(!appUpdateController.canCheckForUpdates)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        #endif
    }

    private var ytDlpStatusRow: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: sectionColumnWidth)
            Color.clear.frame(width: titleColumnWidth)
            Spacer(minLength: 0)

            Group {
                switch state.updateState {
                case .idle:
                    Button(Loc.checkForUpdates(lang), action: state.checkForUpdate)
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .checking:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(Loc.checking(lang)).font(.callout).foregroundStyle(.secondary)
                    }

                case let .available(current, latest):
                    HStack(spacing: 8) {
                        Text(Loc.updateAvailable(current, latest, lang))
                            .font(.callout).foregroundStyle(.orange)
                        Button(Loc.installUpdate(lang), action: state.installUpdate)
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }

                case let .upToDate(version):
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(Loc.upToDate(version, lang)).font(.callout).foregroundStyle(.secondary)
                        Button(Loc.checkAgain(lang), action: state.checkForUpdate)
                            .buttonStyle(.borderless).font(.caption)
                    }

                case let .downloading(progress):
                    HStack(spacing: 8) {
                        Text(Loc.downloadingUpdate(lang)).font(.callout).foregroundStyle(.secondary)
                        ProgressView(value: progress).frame(maxWidth: 140)
                    }

                case .verifying:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(Loc.verifyingInstalling(lang)).font(.callout).foregroundStyle(.secondary)
                    }

                case let .completed(newVersion):
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(Loc.updatedTo(newVersion, lang)).font(.callout).foregroundStyle(.secondary)
                        Button(Loc.checkAgain(lang), action: state.checkForUpdate)
                            .buttonStyle(.borderless).font(.caption)
                    }

                case let .failed(error):
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                            Text(error.message).font(.callout).foregroundStyle(.red).lineLimit(2)
                        }
                        Button(Loc.retry(lang), action: state.checkForUpdate)
                            .buttonStyle(.borderless).font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
    }

    // MARK: - About section

    private var aboutSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("YTTool")
                .font(.title2.weight(.semibold))

            Text("\(Loc.appVersionLabel(lang)) \(appVersion)  ·  \(Loc.buildLabel(lang)) \(appBuild)")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                Link(destination: repoURL) {
                    Label("GitHub", systemImage: "link")
                }

                Label(Loc.privacyTitle(lang), systemImage: "hand.raised")
                    .foregroundStyle(Color.accentColor)
                    .onTapGesture { showsPrivacyInfo.toggle() }
                    .popover(isPresented: $showsPrivacyInfo) {
                        privacyPopover
                    }
            }
            .font(.callout)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var cookiesGuidePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Loc.cookiesGuideTitle(lang))
                .font(.headline)

            Text(Loc.cookiesGuideIntro(lang))
                .font(.callout)
                .foregroundStyle(.secondary)

            // 3-step cards
            let titles = Loc.cookiesGuideStepTitles(lang)
            let details = Loc.cookiesGuideStepDetails(lang)
            VStack(spacing: 12) {
                ForEach(0 ..< titles.count, id: \.self) { i in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Color.accentColor, in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(titles[i])
                                .font(.caption.weight(.semibold))
                            Text(details[i])
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Text(Loc.cookiesGuideWarning(lang))
                .font(.caption)
                .foregroundStyle(.orange)

            Divider()

            Text(Loc.cookiesGuideAdvanced(lang))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: popoverWidth, alignment: .leading)
    }

    private var privacyPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Loc.privacyTitle(lang))
                .font(.headline)

            ForEach(Loc.privacyPoints(lang), id: \.self) { point in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(point)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(width: popoverWidth, alignment: .leading)
    }

    /// Popover width — adaptive so key names (extension, paths) don't break mid-word.
    private var popoverWidth: CGFloat {
        lang == .chinese ? 420 : 460
    }

    // MARK: - Layout primitives

    /// 3-column row: section label | setting name | control — all left-aligned.
    private func settingsRow(
        section: String? = nil,
        title: String,
        help: String? = nil,
        status: String? = nil,
        @ViewBuilder control: () -> some View
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(section ?? "")
                .font(.headline)
                .frame(width: sectionColumnWidth, alignment: .leading)
                .opacity(section != nil ? 1 : 0)

            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout)
                    if let status {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let help, !help.isEmpty {
                    Image(systemName: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(help)
                }
            }
            .frame(width: titleColumnWidth, alignment: .leading)

            control()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
    }

    private func sectionDivider() -> some View {
        Divider()
            .padding(.vertical, 4)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }
}
