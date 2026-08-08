import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Bridges SwiftUI toolbar buttons to the live `NSTextView`'s selection.
///
/// The `RichTextEditor` assigns its `textView` here so a SwiftUI toolbar can
/// act on the current selection using the standard AppKit font/style APIs:
/// `NSFontManager` trait conversion, attribute toggles on the selected range
/// (or `typingAttributes` when nothing is selected), paragraph alignment, and
/// inline image attachments.
@MainActor
public final class RichTextFormatterController: ObservableObject {
    weak var textView: NSTextView?
    /// Set from the representable so attribute-only edits (which don't fire
    /// `textDidChange`) still sync the SwiftUI document + persist.
    var documentBinding: Binding<NSAttributedString>?

    // Active-state mirrors for toolbar highlighting.
    @Published public var boldOn = false
    @Published public var italicOn = false
    @Published public var underlineOn = false
    @Published public var strikethroughOn = false
    @Published public var alignment: NSTextAlignment = .left

    private let fontManager = NSFontManager.shared

    // MARK: - Active state

    public func refreshActiveStates() {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let attrs: [NSAttributedString.Key: Any]
        if range.length == 0 {
            attrs = tv.typingAttributes
        } else {
            attrs = tv.textStorage?.attributes(at: max(range.location, 0),
                                               effectiveRange: nil) ?? tv.typingAttributes
        }
        let font = (attrs[.font] as? NSFont) ?? tv.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let traits = fontManager.traits(of: font)
        boldOn = (traits.rawValue & NSFontTraitMask.boldFontMask.rawValue) != 0
        italicOn = (traits.rawValue & NSFontTraitMask.italicFontMask.rawValue) != 0
        underlineOn = isStyleOn(attrs[.underlineStyle])
        strikethroughOn = isStyleOn(attrs[.strikethroughStyle])
        if let para = attrs[.paragraphStyle] as? NSParagraphStyle {
            alignment = para.alignment
        } else {
            alignment = .left
        }
    }

    private func isStyleOn(_ value: Any?) -> Bool {
        guard let n = value as? NSNumber else { return false }
        return n.intValue != 0
    }

    // MARK: - Font traits

    public func toggleBold() {
        toggleFontTrait { font in
            let hasBold = (fontManager.traits(of: font).rawValue & NSFontTraitMask.boldFontMask.rawValue) != 0
            return hasBold
                ? fontManager.convert(font, toNotHaveTrait: .boldFontMask)
                : fontManager.convert(font, toHaveTrait: .boldFontMask)
        }
    }

    public func toggleItalic() {
        toggleFontTrait { font in
            let hasItalic = (fontManager.traits(of: font).rawValue & NSFontTraitMask.italicFontMask.rawValue) != 0
            return hasItalic
                ? fontManager.convert(font, toNotHaveTrait: .italicFontMask)
                : fontManager.convert(font, toHaveTrait: .italicFontMask)
        }
    }

    private func toggleFontTrait(convert: (NSFont) -> NSFont?) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let baseFont = tv.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)

        if range.length == 0 {
            let current = (tv.typingAttributes[.font] as? NSFont) ?? baseFont
            let next = convert(current) ?? current
            var attrs = tv.typingAttributes
            attrs[.font] = next
            tv.typingAttributes = attrs
        } else {
            guard let storage = tv.textStorage else { return }
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                let current = (value as? NSFont) ?? baseFont
                let next = convert(current) ?? current
                storage.addAttribute(.font, value: next, range: subRange)
            }
            storage.endEditing()
        }
        commit()
        refreshActiveStates()
    }

    // MARK: - Underline / Strikethrough

    public func toggleUnderline() {
        toggleStyleAttribute(.underlineStyle, onValue: NSUnderlineStyle.single.rawValue)
    }

    public func toggleStrikethrough() {
        toggleStyleAttribute(.strikethroughStyle, onValue: NSUnderlineStyle.single.rawValue)
    }

    private func toggleStyleAttribute(_ key: NSAttributedString.Key, onValue: Int) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        if range.length == 0 {
            var attrs = tv.typingAttributes
            if isStyleOn(attrs[key]) {
                attrs.removeValue(forKey: key)
            } else {
                attrs[key] = NSNumber(value: onValue)
            }
            tv.typingAttributes = attrs
        } else {
            guard let storage = tv.textStorage else { return }
            storage.beginEditing()
            storage.enumerateAttribute(key, in: range, options: []) { value, subRange, _ in
                var attrs = storage.attributes(at: subRange.location, longestEffectiveRange: nil, in: subRange)
                if isStyleOn(value) {
                    attrs.removeValue(forKey: key)
                } else {
                    attrs[key] = NSNumber(value: onValue)
                }
                storage.setAttributes(attrs, range: subRange)
            }
            storage.endEditing()
        }
        commit()
        refreshActiveStates()
    }

    // MARK: - Alignment

    public func setAlignment(_ align: NSTextAlignment) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        if range.length == 0 {
            let paragraph = (tv.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()
            paragraph.alignment = align
            var attrs = tv.typingAttributes
            attrs[.paragraphStyle] = paragraph
            tv.typingAttributes = attrs
        } else {
            guard let storage = tv.textStorage else { return }
            let parRange = (storage.string as NSString).paragraphRange(for: range)
            let existing = (storage.attribute(.paragraphStyle, at: parRange.location, effectiveRange: nil) as? NSParagraphStyle)
                ?? NSParagraphStyle.default
            let paragraph = existing.mutableCopy() as! NSMutableParagraphStyle
            paragraph.alignment = align
            storage.addAttribute(.paragraphStyle, value: paragraph, range: parRange)
        }
        commit()
        refreshActiveStates()
    }

    // MARK: - Link

    public func toggleLink() {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        var urlValue: URL?
        if let s = NSPasteboard.general.string(forType: .URL), let u = URL(string: s) {
            urlValue = u
        } else if let s = NSPasteboard.general.string(forType: .string),
                  let u = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)),
                  u.scheme != nil {
            urlValue = u
        }
        guard let url = urlValue else {
            let panel = NSAlert()
            panel.messageText = "Link URL"
            panel.informativeText = "Copy a URL to the clipboard, then tap Link."
            panel.addButton(withTitle: "OK")
            panel.runModal()
            return
        }
        if range.length == 0 {
            var attrs = tv.typingAttributes
            attrs[.link] = url
            tv.typingAttributes = attrs
        } else {
            tv.textStorage?.addAttribute(.link, value: url, range: range)
        }
        commit()
        refreshActiveStates()
    }

    // MARK: - Image

    public func insertImage() {
        guard let tv = textView else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Choose an image"
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }

        // Auto-fit: never wider than the container minus padding, capped at 240pt
        // so dropped/imported photos don't appear at full pixel size.
        let containerWidth = tv.textContainer?.size.width ?? tv.bounds.width
        guard let container = tv.textContainer, containerWidth > 0 else { return }
        let maxWidth = max(min(containerWidth - 16, 240), 100)
        let displaySize = ScalableImageAttachment.fit(image: image, maxWidth: maxWidth)
        let attachment = ScalableImageAttachment(image: image, displaySize: displaySize)
        let attrString = NSAttributedString(attachment: attachment)
        guard let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        if range.length == 0 {
            storage.insert(attrString, at: range.location)
        } else {
            storage.replaceCharacters(in: range, with: attrString)
        }
        tv.setSelectedRange(NSRange(location: range.location + attrString.length, length: 0))
        commit()
        refreshActiveStates()
    }

    // MARK: - Sync

    private func commit() {
        guard let storage = textView?.textStorage else { return }
        let copy = storage.copy() as? NSAttributedString ?? NSAttributedString()
        documentBinding?.wrappedValue = copy
    }
}

// MARK: - Toolbar view

public struct RichTextToolbar: View {
    @ObservedObject public var formatter: RichTextFormatterController

    public init(formatter: RichTextFormatterController) {
        self.formatter = formatter
    }

    public var body: some View {
        HStack(spacing: 2) {
            Group {
                toggleButton(symbol: "bold", on: formatter.boldOn, help: "Bold", action: formatter.toggleBold)
                toggleButton(symbol: "italic", on: formatter.italicOn, help: "Italic", action: formatter.toggleItalic)
                toggleButton(symbol: "underline", on: formatter.underlineOn, help: "Underline", action: formatter.toggleUnderline)
                toggleButton(symbol: "strikethrough", on: formatter.strikethroughOn, help: "Strikethrough", action: formatter.toggleStrikethrough)
            }
            divider
            Group {
                toggleButton(symbol: "text.alignleft", on: formatter.alignment == .left, help: "Align left", action: { formatter.setAlignment(.left) })
                toggleButton(symbol: "text.aligncenter", on: formatter.alignment == .center, help: "Align center", action: { formatter.setAlignment(.center) })
                toggleButton(symbol: "text.alignright", on: formatter.alignment == .right, help: "Align right", action: { formatter.setAlignment(.right) })
            }
            divider
            Group {
                toggleButton(symbol: "link", on: false, help: "Link", action: formatter.toggleLink)
                toggleButton(symbol: "photo", on: false, help: "Image", action: formatter.insertImage)
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func toggleButton(symbol: String, on: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(on ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .foregroundStyle(on ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
