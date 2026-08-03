import Foundation
import AppKit

/// v3.5: The Custom bucket is a fully user-authored rich-text footer (bold,
/// italic, color, and an embedded image via `NSTextAttachment`). This utility
/// owns the only two hard jobs:
///   1. Round-tripping the footer through SwiftData as RTFD `Data` (RTFD keeps
///      attachment image payloads, plain RTF would drop them).
///   2. Writing the footer to the pasteboard as RTF + RTFD + plain string so
///      Mail / Notes / Pages pick the richest representation they understand.
public enum RichTextFooter {

    /// Serialize an attributed string to RTFD data (includes image attachments).
    public static func data(from attributed: NSAttributedString) -> Data? {
        let attrs: [NSAttributedString.DocumentAttributeKey: Any] = [.documentType: NSAttributedString.DocumentType.rtfd]
        return try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: attrs
        )
    }

    /// Deserialize RTFD data back into an attributed string. `nil` data or a
    /// parse failure returns `nil`.
    public static func attributed(from data: Data?) -> NSAttributedString? {
        guard let data, !data.isEmpty else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: NSAttributedString.DocumentType.rtfd]
        return try? NSAttributedString(
            data: data,
            options: options,
            documentAttributes: nil
        )
    }

    /// A footer is "configured" when it exists and has more than whitespace.
    public static func isEmpty(_ data: Data?) -> Bool {
        guard let data, !data.isEmpty,
              let attributed = attributed(from: data) else { return true }
        return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Write the footer to `pasteboard` as `.rtf` + `.rtfd` + `.string`.
    /// Returns `false` if the pasteboard refused the write.
    @discardableResult
    public static func writeRTF(_ attributed: NSAttributedString, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        let full = NSRange(location: 0, length: attributed.length)
        let rtfAttrs: [NSAttributedString.DocumentAttributeKey: Any] = [.documentType: NSAttributedString.DocumentType.rtf]
        let rtfdAttrs: [NSAttributedString.DocumentAttributeKey: Any] = [.documentType: NSAttributedString.DocumentType.rtfd]
        if let rtf = try? attributed.data(from: full, documentAttributes: rtfAttrs) {
            item.setData(rtf, forType: .rtf)
        }
        if let rtfd = try? attributed.data(from: full, documentAttributes: rtfdAttrs) {
            item.setData(rtfd, forType: .rtfd)
        }
        item.setString(attributed.string, forType: .string)
        return pasteboard.writeObjects([item])
    }
}
