import SwiftUI

struct LogPanelView: View {
    let entries: [AppLogEntry]
    var language: AppLanguage = .english
    @State private var isExpanded = false
    @State private var lastSeenErrorCount = 0

    private var errorCount: Int {
        entries.filter { $0.level == .error }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Loc.sessionLog(language))
                    .font(.headline)

                if errorCount > 0 {
                    Text(Loc.errorBadge(errorCount, language))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red, in: Capsule())
                }

                Spacer()
                Text(Loc.nEntries(entries.count, language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(isExpanded ? Loc.hideLogs(language) : Loc.showLogs(language)) {
                    isExpanded.toggle()
                }
                .buttonStyle(.borderless)
            }
            .onChange(of: errorCount) { _, newValue in
                if newValue > lastSeenErrorCount {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isExpanded = true
                    }
                }
                lastSeenErrorCount = newValue
            }

            if isExpanded {
                expandedPanel
            }
        }
    }

    private var expandedPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(entries) { entry in
                        row(entry)
                            .id(entry.id)
                    }
                }
            }
            .frame(maxHeight: 190)
            .padding(12)
            .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
            .onAppear {
                scrollToLastEntry(proxy)
            }
            .onChange(of: entries.count) {
                scrollToLastEntry(proxy)
            }
        }
    }

    private func row(_ entry: AppLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(timestampFormatter.string(from: entry.timestamp))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(entry.scope.rawValue)
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
                Text(entry.level.rawValue)
                    .font(.caption2.monospaced())
                    .foregroundStyle(color(for: entry.level))
            }

            Text(entry.message)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private func color(for level: AppLogLevel) -> Color {
        switch level {
        case .info:
            .secondary
        case .success:
            .green
        case .warning:
            .orange
        case .error:
            .red
        }
    }

    private func scrollToLastEntry(_ proxy: ScrollViewProxy) {
        guard let lastID = entries.last?.id else {
            return
        }
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }
}

private let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
}()
