import SwiftUI
import AppKit

/// NSTextView-backed rich-text editor for the "After Signoff" footer.
///
/// A thin `NSViewRepresentable` wrapper around `NSTextView` that enables
/// rich-text editing (font styles, alignment, images) inside the Settings
/// flow. A `RichTextFormatterController` is shared between this view and the
/// `RichTextToolbar` overlay so the SwiftUI buttons can act on the live text
/// view's selection using the standard AppKit font/style APIs.
@MainActor
public struct RichTextEditor: NSViewRepresentable {
    @Binding public var document: NSAttributedString
    public let placeholder: String
    public let formatter: RichTextFormatterController

    public init(document: Binding<NSAttributedString>,
                placeholder: String = "",
                formatter: RichTextFormatterController) {
        self._document = document
        self.placeholder = placeholder
        self.formatter = formatter
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = ResizingTextView(frame: .zero)
        scrollView.documentView = textView

        // Rich text + image embedding.
        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isFieldEditor = false
        textView.drawsBackground = false
        textView.usesFontPanel = false  // settings-style editor, not a full word processor
        textView.smartInsertDeleteEnabled = true

        // Autoresize so width tracks the scroll view and height grows with content.
        textView.autoresizingMask = [.width] as NSView.AutoresizingMask
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 4

        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        textView.delegate = context.coordinator
        textView.textStorage?.setAttributedString(document)

        // Wire the formatter to this live text view.
        context.coordinator.formatter = formatter
        formatter.textView = textView
        formatter.documentBinding = $document
        formatter.refreshActiveStates()

        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.formatter = formatter
        formatter.textView = textView
        formatter.documentBinding = $document

        // Avoid clobbering an in-flight edit when the binding hasn't changed.
        let current = textView.textStorage?.copy() as? NSAttributedString ?? NSAttributedString()
        if !current.isEqual(to: document) {
            textView.textStorage?.setAttributedString(document)
        }
        formatter.refreshActiveStates()
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        weak var formatter: RichTextFormatterController?
        @Binding var document: NSAttributedString

        public init(formatter: RichTextFormatterController, document: Binding<NSAttributedString>) {
            self.formatter = formatter
            self._document = document
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let attr = textView.textStorage?.copy() as? NSAttributedString ?? NSAttributedString()
            DispatchQueue.main.async {
                self.document = attr
            }
            formatter?.refreshActiveStates()
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            formatter?.refreshActiveStates()
        }

        public func textViewDidChangeTypingAttributes(_ notification: Notification) {
            formatter?.refreshActiveStates()
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(formatter: formatter, document: $document)
    }
}

/// SwiftUI placeholder overlay drawn over `RichTextEditor` when its document
/// is empty. Hit-testing is disabled so clicks fall through to the NSTextView.
public struct RichTextPlaceholder: View {
    let document: NSAttributedString
    let text: String

    public init(_ text: String, document: NSAttributedString) {
        self.text = text
        self.document = document
    }

    public var body: some View {
        Group {
            if document.string.isEmpty && !text.isEmpty {
                Text(text)
                    .font(.system(size: NSFont.systemFontSize))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)
            }
        }
    }
}
