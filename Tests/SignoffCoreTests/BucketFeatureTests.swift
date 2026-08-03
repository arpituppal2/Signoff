import XCTest
import AppKit
@testable import SignoffCore

/// v3.5: bucket renames/reorder, NSFW prompt override, and the Custom bucket's
/// rich-text footer (RTFD storage + pasteboard contract).
@MainActor
final class BucketFeatureTests: XCTestCase {

    // MARK: - Bucket defaults

    func testDefaultBucketsAreNormalProfessionalCynicalCustom() {
        let buckets = Bucket.defaultBuckets()
        XCTAssertEqual(buckets.map(\.name), ["Normal", "Professional", "Cynical", "Custom"])
        XCTAssertEqual(buckets.map(\.id),
                       [BucketID.standard.rawValue,
                        BucketID.professional.rawValue,
                        BucketID.unhinged.rawValue,
                        BucketID.custom.rawValue])
        XCTAssertEqual(buckets.map(\.sortOrder), [0, 1, 2, 3])
        XCTAssertEqual(buckets.map(\.iconSymbol).count, 4)
    }

    func testCynicalDefaultsToDeadpanAndNSFWOff() {
        guard let cynical = Bucket.defaultBuckets().first(where: { $0.id == BucketID.unhinged.rawValue }) else {
            return XCTFail("Cynical bucket missing")
        }
        XCTAssertEqual(cynical.unhingedLevel, .cynical)
        XCTAssertFalse(cynical.nsfwEnabled)
    }

    // MARK: - NSFW prompt override

    func testNSFWOverridePresentInInstructionsWhenEnabled() {
        let template = PromptTemplate.load(bucket: BucketID.unhinged.rawValue) ?? .fallback
        let profile = UserProfileSnapshot(profile: nil)

        let on = PromptComposer.compose(
            template: template, profile: profile, recentTexts: [], nsfwEnabled: true)
        XCTAssertTrue(on.instructions.contains("Content policy override: profanity and adult humor are permitted"),
                      "NSFW enable must lift the template's profanity ban")

        let off = PromptComposer.compose(
            template: template, profile: profile, recentTexts: [], nsfwEnabled: false)
        XCTAssertFalse(off.instructions.contains("Content policy override"),
                       "NSFW disable must keep the default rules untouched")
    }

    // MARK: - Rich text footer (Custom bucket)

    func testRichTextFooterRoundTripsFormatting() throws {
        let attributed = NSMutableAttributedString(
            string: "Thanks — see you Monday.",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 14),
                         .foregroundColor: NSColor.systemRed]
        )
        attributed.append(NSAttributedString(
            string: "\n— Alex",
            attributes: [.font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 12), toHaveTrait: .italicFontMask)]
        ))

        let data = try XCTUnwrap(RichTextFooter.data(from: attributed))
        let roundtrip = try XCTUnwrap(RichTextFooter.attributed(from: data))
        XCTAssertEqual(roundtrip.string, attributed.string)

        let bold = roundtrip.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(bold?.fontDescriptor.symbolicTraits.contains(.bold), true)
    }

    func testRichTextFooterRoundTripsEmbeddedImage() throws {
        let rep = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        )
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: 0, width: 8, height: 8)
        let attributed = NSMutableAttributedString(attachment: attachment)
        attributed.append(NSAttributedString(string: " — from my desk"))

        let data = try XCTUnwrap(RichTextFooter.data(from: attributed))
        let roundtrip = try XCTUnwrap(RichTextFooter.attributed(from: data))

        var attachmentCount = 0
        roundtrip.enumerateAttribute(.attachment, in: NSRange(location: 0, length: roundtrip.length)) { value, _, _ in
            if value is NSTextAttachment { attachmentCount += 1 }
        }
        XCTAssertGreaterThanOrEqual(attachmentCount, 1,
                                    "RTFD round-trip must preserve the embedded image attachment")
        XCTAssertTrue(roundtrip.string.contains("from my desk"))
    }

    func testWriteRTFIncludesPlainAndRTF() throws {
        let attributed = NSAttributedString(
            string: "Onward.",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        let pb = NSPasteboard(name: NSPasteboard.Name("signoff.tests.rtf"))
        pb.clearContents()

        XCTAssertTrue(RichTextFooter.writeRTF(attributed, to: pb))
        XCTAssertEqual(pb.string(forType: .string), "Onward.")
        XCTAssertNotNil(pb.data(forType: .rtf), "RTF representation must be written")
    }

    func testIsEmptyTreatsWhitespaceAsUnconfigured() throws {
        let empty = try XCTUnwrap(RichTextFooter.data(from: NSAttributedString(string: "  \n ")))
        XCTAssertTrue(RichTextFooter.isEmpty(empty))
        XCTAssertTrue(RichTextFooter.isEmpty(nil))

        let real = try XCTUnwrap(RichTextFooter.data(from: NSAttributedString(string: "Thanks!")))
        XCTAssertFalse(RichTextFooter.isEmpty(real))
    }
}
