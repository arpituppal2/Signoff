import SwiftUI
import AppKit
import SignoffCore

/// Settings editor for the Custom bucket's user-authored rich-text footer.
/// Wraps an `NSTextView` (editable, rich text) behind a small format toolbar:
/// bold / italic / underline / text color / insert image / clear. Every change
/// is persisted straight to `bucket.footerRTFData` as RTFD so formatting and
/// embedded images survive copy + paste.
@MainActor
public struct RichFooterEditor: View {
    let bucket: Bucket
    @StateObject private var controller: RichTextEditorController

    public init(bucket: Bucket) {
        self.bucket = bucket
        _controller = StateObject(wrappedValue: RichTextEditorController(bucket: bucket))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Brand.Layout.spacingS) {
            HStack(spacing: 4) {
                formatButton("bold", help: "Bold") { controller.toggleBold() }
                formatButton("italic", help: "Italic") { controller.toggleItalic() }
                formatButton("underline", help: "Underline") { controller.toggleUnderline() }
                formatButton("textformat", help: "Text color") { controller.pickColor() }
                formatButton("photo.on.rectangle", help: "Insert image") { controller.insertImage() }

                Spacer()

                Button(role: .destructive) {
                    controller.clearFooter()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .font(.caption)
                }
                .help("Remove the footer and start over")
                .disabled(controller.isEmpty)
            }
            .buttonStyle(.borderless)

            FooterEditorTextView(controller: controller)
                .frame(minHeight: 150)
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.Layout.radiusM, style: .continuous)
                        .stroke(Brand.Surface.divider(for: .light), lineWidth: Brand.Layout.hairline)
                )
                .clipShape(RoundedRectangle(cornerRadius: Brand.Layout.radiusM, style: .continuous))
        }
    }

    private func formatButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Shared controller for the editor — owned by SwiftUI (`@StateObject`), talks
/// to the `NSTextView` through a weak reference so there is no retain cycle
/// (`NSTextView.delegate` is itself weak).
@MainActor
final class RichTextEditorController: NSObject, ObservableObject, NSTextViewDelegate {
    let bucket: Bucket
    weak var textView: NSTextView?

    @Published private(set) var isEmpty = true

    init(bucket: Bucket) {
        self.bucket = bucket
        super.init()
    }

    func configure(_ textView: NSTextView) {
        self.textView = textView
        textView.delegate = self
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false

        if let footer = RichTextFooter.attributed(from: bucket.footerRTFData) {
            textView.textStorage?.setAttributedString(footer)
        }
        refreshEmptyState()
    }

    func textDidChange(_ notification: Notification) {
        save()
    }

    func save() {
        guard let textView else { return }
        let storage = textView.textStorage ?? NSMutableAttributedString()
        bucket.footerRTFData = RichTextFooter.data(from: storage)
        bucket.updatedAt = Date()
        try? PersistenceController.shared.context.save()
        refreshEmptyState()
    }

    private func refreshEmptyState() {
        isEmpty = RichTextFooter.isEmpty(bucket.footerRTFData)
    }

    // MARK: - Toolbar actions

    func toggleBold() {
        toggleFontTrait(.boldFontMask)
    }

    func toggleItalic() {
        toggleFontTrait(.italicFontMask)
    }

    func toggleUnderline() {
        guard let textView else { return }
        let range = textView.selectedRange()
        let flip: (Int) -> Int = { raw in
            (raw & NSUnderlineStyle.single.rawValue) != 0 ? 0 : NSUnderlineStyle.single.rawValue
        }
        if range.length > 0 {
            textView.textStorage?.beginEditing()
            textView.textStorage?.enumerateAttribute(.underlineStyle, in: range) { value, r, _ in
                let raw = (value as? Int) ?? 0
                textView.textStorage?.addAttribute(.underlineStyle, value: flip(raw), range: r)
            }
            textView.textStorage?.endEditing()
        } else {
            let raw = (textView.typingAttributes[.underlineStyle] as? Int) ?? 0
            textView.typingAttributes[.underlineStyle] = flip(raw)
        }
        save()
    }

    /// Flip a font trait (bold/italic) on the selection, or on the typing
    /// attributes when nothing is selected, so the next keystroke inherits it.
    private func toggleFontTrait(_ trait: NSFontTraitMask) {
        guard let textView else { return }
        let fm = NSFontManager.shared
        let flip: (NSFont) -> NSFont = { font in
            fm.traits(of: font).contains(trait)
                ? fm.convert(font, toNotHaveTrait: trait)
                : fm.convert(font, toHaveTrait: trait)
        }
        let range = textView.selectedRange()
        if range.length > 0 {
            textView.textStorage?.beginEditing()
            textView.textStorage?.enumerateAttribute(.font, in: range) { value, r, _ in
                if let font = value as? NSFont {
                    textView.textStorage?.addAttribute(.font, value: flip(font), range: r)
                }
            }
            textView.textStorage?.endEditing()
        } else if let font = textView.typingAttributes[.font] as? NSFont {
            textView.typingAttributes[.font] = flip(font)
        }
        save()
    }

    func pickColor() {
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorPicked(_:)))
        panel.isContinuous = true
        panel.orderFront(nil)
    }

    @objc private func colorPicked(_ sender: NSColorPanel) {
        guard let textView else { return }
        textView.setTextColor(sender.color, range: textView.selectedRange())
        save()
    }

    func insertImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .gif, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url,
                  let data = try? Data(contentsOf: url) else { return }
            self?.attachImage(data: data)
        }
    }

    private func attachImage(data: Data) {
        guard let textView, let image = NSImage(data: data) else { return }
        let attachment = NSTextAttachment()
        attachment.image = image
        // Cap the inline image at 240pt wide so it fits the compose column.
        let maxWidth: CGFloat = 240
        if image.size.width > maxWidth {
            let scale = maxWidth / image.size.width
            attachment.bounds = NSRect(
                x: 0, y: 0,
                width: maxWidth,
                height: image.size.height * scale
            )
        }
        textView.insertText(NSAttributedString(attachment: attachment), replacementRange: textView.selectedRange())
        save()
    }

    func clearFooter() {
        textView?.textStorage?.setAttributedString(NSAttributedString(string: ""))
        save()
    }
}

/// The `NSTextView` host. `makeNSView` configures the shared controller;
/// `updateNSView` only re-syncs when the source footer changes outside the
/// editor (never during normal editing — textDidChange owns persistence).
private struct FooterEditorTextView: NSViewRepresentable {
    let controller: RichTextEditorController

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 150))
        controller.configure(textView)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 150))
        scroll.hasVerticalScroller = true
        scroll.documentView = textView
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // No-op — see doc comment.
    }
}

/// Read-only rich-text renderer for the menu-bar popover preview. Shows the
/// Custom footer exactly as it will paste (formatting + embedded image).
@MainActor
public struct AttributedStringPreview: NSViewRepresentable {
    let attributed: NSAttributedString

    public init(attributed: NSAttributedString) {
        self.attributed = attributed
    }

    public func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.isRichText = true
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.textStorage?.setAttributedString(attributed)
        return textView
    }

    public func updateNSView(_ textView: NSTextView, context: Context) {
        textView.textStorage?.setAttributedString(attributed)
    }
}
