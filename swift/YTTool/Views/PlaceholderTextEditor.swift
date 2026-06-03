import AppKit
import SwiftUI

struct PlaceholderTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var font: NSFont = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PlaceholderNSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = font
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.placeholderString = placeholder
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PlaceholderNSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.placeholderString = placeholder
        textView.font = font
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlaceholderTextEditor

        init(_ parent: PlaceholderTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

private class PlaceholderNSTextView: NSTextView {
    var placeholderString: String = "" {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if string.isEmpty, !placeholderString.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            let inset = textContainerInset
            let padding = textContainer?.lineFragmentPadding ?? 5
            let origin = NSPoint(x: inset.width + padding, y: inset.height)
            NSAttributedString(string: placeholderString, attributes: attrs).draw(at: origin)
        }
    }
}
