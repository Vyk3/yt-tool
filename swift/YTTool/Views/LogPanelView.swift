import SwiftUI

struct LogPanelView: View {
    let entries: [AppLogEntry]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Session Log")
                    .font(.headline)
                Spacer()
                Text("\(entries.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(isExpanded ? "Hide Logs" : "Show Logs") {
                    isExpanded.toggle()
                }
                .buttonStyle(.borderless)
            }

            if isExpanded {
                expandedPanel
            } else {
                collapsedPanel
            }
        }
    }

    private var collapsedPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entries.isEmpty {
                Text("Probe and download events will appear here during this app session.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Latest activity")
                    .font(.subheadline.weight(.semibold))
                ForEach(Array(entries.suffix(2))) { entry in
                    row(entry)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
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
            .onChange(of: entries.count) { _ in
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
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
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
