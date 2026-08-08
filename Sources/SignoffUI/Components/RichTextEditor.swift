import SwiftUI
import AppKit

/// NSTextView-backed rich-text editor for the "After Signoff" footer.
///
/// A thin `NSViewRepresentable` wrapper around `NSTextView` that enables
/// rich-text editing (font styles, alignment, images) inside the Settings
/// flow. A `RichTextFormatterController` is shared between this view and the
/// `RichTextToolbar` overlay so the SwiftUI buttons can act on the live text
/// view's selection using the standard AppKit font/style APIs.
///
/// Height is content-driven: the scroll view grows up to the SwiftUI `frame`
/// `idealHeight`, then scrolls. So the box is resizable — it expands as you
/// add lines, and only scrolls past that.
@MainActor
public struct RichTextEditor: NSViewRepresentable {
    @Binding public var document: NSAttributedString
    public let placeholder: String
    public let formatter: RichTextFormatterController
    /// Informs SwiftUI of the content's natural height so the surrounding
    /// `.frame(idealHeight:)` can grow the box with typed content.
    public var onMeasuredHeight: ((CGFloat) -> Void)?

    public init(document: Binding<NSAttributedString>,
                placeholder: String = "",
                formatter: RichTextFormatterController,
                onMeasuredHeight: ((CGFloat) -> Void)? = nil) {
        self._document = document
        self.placeholder = placeholder
        self.formatter = formatter
        self.onMeasuredHeight = onMeasuredHeight
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        // Autoresize the scroll view itself so SwiftUI can drive its height
        // from the measured content; the text view fills it.
        scrollView.autoresizingMask = [.width, .height]

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

        // Width tracks the scroll view; height grows unbounded with content.
        textView.autoresizingMask = [.width] as NSView.AutoresizingMask
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 4
        // Let the text container expand its layout height to fit content so
        // the measured content height (used for the SwiftUI frame) is accurate.
        textView.textContainer?.size = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        textView.delegate = context.coordinator
        textView.textStorage?.setAttributedString(document)

        // Wire the formatter to this live text view.
        context.coordinator.formatter = formatter
        context.coordinator.scrollView = scrollView
        context.coordinator.onMeasuredHeight = onMeasuredHeight
        formatter.textView = textView
        formatter.documentBinding = $document
        formatter.refreshActiveStates()

        // Measure initial content height so the box opens sized to its content.
        DispatchQueue.main.async { context.coordinator.reportMeasuredHeight() }

        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.formatter = formatter
        context.coordinator.scrollView = nsView
        context.coordinator.onMeasuredHeight = onMeasuredHeight
        formatter.textView = textView
        formatter.documentBinding = $document

        // Avoid clobbering an in-flight edit when the binding hasn't changed.
        let current = textView.textStorage?.copy() as? NSAttributedString ?? NSAttributedString()
        if !current.isEqual(to: document) {
            textView.textStorage?.setAttributedString(document)
        }
        formatter.refreshActiveStates()

        // Re-measure whenever the document changes from outside (e.g. undo).
        DispatchQueue.main.async { context.coordinator.reportMeasuredHeight() }
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        weak var formatter: RichTextFormatterController?
        weak var scrollView: NSScrollView?
        var onMeasuredHeight: ((CGFloat) -> Void)?
        @Binding var document: NSAttributedString

        public init(formatter: RichTextFormatterController, document: Binding<NSAttributedString>) {
            self.formatter = formatter
            self._document = document
        }

        /// Measures the text view's natural content height and reports it so
        /// SwiftUI can grow the editor frame with typed content.
        func reportMeasuredHeight() {
            guard let scrollView, let textView = scrollView.documentView as? NSTextView,
                  let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
                return
            }
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let inset = textView.textContainerInset.height * 2
            // Add a little breathing room and the scroll view's scroller area.
            let height = ceil(usedRect.height + inset) + 4
            onMeasuredHeight?(max(height, 96))
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let attr = textView.textStorage?.copy() as? NSAttributedString ?? NSAttributedString()
            DispatchQueue.main.async {
                self.document = attr
                self.reportMeasuredHeight()
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
