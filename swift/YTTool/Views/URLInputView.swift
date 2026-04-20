import SwiftUI

struct URLInputView: View {
    @Binding var inputURL: String
    let probeState: ProbeState
    let selectedDirectory: URL?
    let onProbe: () -> Void
    let onSelectDirectory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("URL")
                .font(.headline)

            TextField("https://example.com/video", text: $inputURL, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1 ... 3)
                .onSubmit { if canProbe { onProbe() } }

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
