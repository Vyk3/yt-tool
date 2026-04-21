import SwiftUI
import UniformTypeIdentifiers

struct URLInputView: View {
    @Binding var inputURL: String
    let probeState: ProbeState
    let selectedDirectory: URL?
    let onProbe: () -> Void
    let onSelectDirectory: () -> Void
    let onClearDirectory: () -> Void
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("URL")
                .font(.headline)

            TextField("https://example.com/video", text: $inputURL, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1 ... 3)
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
                .onSubmit { if canProbe { onProbe() } }
                .onDrop(
                    of: [UTType.url.identifier, UTType.plainText.identifier],
                    isTargeted: $isDropTargeted,
                    perform: handleDrop(providers:)
                )

            Text("You can also drag a video URL into the field.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Label(probeState.statusLabel, systemImage: probeState.symbolName)
                    .foregroundStyle(probeState.tintColor)

                Button(action: onSelectDirectory) {
                    Label(
                        selectedDirectory?.lastPathComponent ?? "Choose folder…",
                        systemImage: "folder"
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

                if selectedDirectory != nil {
                    Button(action: onClearDirectory) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Clear selected folder")
                }

                Spacer(minLength: 0)

                Button("Probe", action: onProbe)
                    .keyboardShortcut(.return)
                    .disabled(!canProbe)
            }
        }
    }

    private var canProbe: Bool {
        !inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && probeState != .loading
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    if let value = extractDroppedString(from: item) {
                        DispatchQueue.main.async {
                            inputURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }
                return true
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    if let value = extractDroppedString(from: item) {
                        DispatchQueue.main.async {
                            inputURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }
                return true
            }
        }

        return false
    }
}

private func extractDroppedString(from item: NSSecureCoding?) -> String? {
    switch item {
    case let url as URL:
        return url.absoluteString
    case let string as String:
        return string
    case let data as Data:
        return String(data: data, encoding: .utf8)
    case let nsString as NSString:
        return nsString as String
    default:
        return nil
    }
}

private extension ProbeState {
    var statusLabel: String {
        switch self {
        case .idle: return "Idle"
        case .loading: return "Probing…"
        case .success(let info): return "Ready: \(info.title)"
        case .failure(let error): return error.message
        }
    }

    var symbolName: String {
        switch self {
        case .idle: return "circle.dotted"
        case .loading: return "bolt.horizontal.circle"
        case .success: return "checkmark.circle"
        case .failure: return "xmark.octagon"
        }
    }

    var tintColor: Color {
        switch self {
        case .idle: return .secondary
        case .loading: return .orange
        case .success: return .green
        case .failure: return .red
        }
    }
}
