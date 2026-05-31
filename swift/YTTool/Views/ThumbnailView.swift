import SwiftUI

struct ThumbnailView: View {
    let url: String?
    var duration: TimeInterval?
    var targetSize: CGSize = CGSize(width: 64, height: 36)

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else if failed || url == nil {
                    placeholder
                } else {
                    Rectangle()
                        .fill(.quaternary)
                }
            }
            .frame(width: targetSize.width, height: targetSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            if let duration, image != nil {
                durationBadge(duration)
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
                .font(.system(size: min(targetSize.width, targetSize.height) * 0.35))
        }
    }

    private func durationBadge(_ seconds: TimeInterval) -> some View {
        Text(formatDuration(seconds))
            .font(.system(size: 9, weight: .medium).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
            .padding(3)
    }

    private func loadImage() async {
        guard let url, !url.isEmpty else {
            failed = true
            return
        }
        image = nil
        failed = false
        let loaded = await ThumbnailLoader.shared.load(url: url, targetSize: targetSize)
        if let loaded {
            image = loaded
        } else {
            failed = true
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
