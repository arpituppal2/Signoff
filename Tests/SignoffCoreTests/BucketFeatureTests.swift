import Testing
import AppKit
@testable import SignoffCore

/// v3.5: bucket renames/reorder, NSFW prompt override, and the Custom bucket's
/// rich-text footer (RTFD storage + pasteboard contract).
@MainActor
struct BucketFeatureTests {

    // MARK: - Bucket defaults

    @Test("Default buckets are Normal, Professional, Cynical")
    func defaultBucketsAreNormalProfessionalCynical() {
        let buckets = Bucket.defaultBuckets()
        #expect(buckets.map(\.name) == ["Normal", "Professional", "Cynical"])
        #expect(buckets.map(\.id) == [
            BucketID.standard.rawValue,
            BucketID.professional.rawValue,
            BucketID.unhinged.rawValue
        ])
        #expect(buckets.map(\.sortOrder) == [0, 1, 2])
        #expect(buckets.map(\.iconSymbol).count == 3)
    }

    @Test("Cynical defaults to Deadpan and NSFW off")
    func cynicalDefaultsToDeadpanAndNSFWOff() {
        guard let cynical = Bucket.defaultBuckets().first(where: { $0.id == BucketID.unhinged.rawValue }) else {
            Issue.record("Cynical bucket missing")
            return
        }
        #expect(cynical.unhingedLevel == .cynical)
        #expect(cynical.nsfwEnabled == false)
    }

    // MARK: - NSFW prompt override (removed - triggers content filter)

    @Test("NSFW override not in instructions")
    func nsfwOverrideNotInInstructions() async throws {
        let template = await PromptTemplate.load(bucket: BucketID.unhinged.rawValue) ?? .fallback
        let profile = UserProfileSnapshot(profile: nil)

        let on = PromptComposer.compose(
            template: template, profile: profile, recentTexts: [], nsfwEnabled: true)
        // NSFW toggle should not add anything to instructions (removed per Arch-4)
        #expect(!on.instructions.contains("Content policy override"),
                   "NSFW enable must NOT add content policy override to instructions")

        let off = PromptComposer.compose(
            template: template, profile: profile, recentTexts: [], nsfwEnabled: false)
        #expect(!off.instructions.contains("Content policy override"),
                   "NSFW disable must keep the default rules untouched")
    }

    // MARK: - Rich text footer (Custom bucket)

    @Test("Rich text footer round trips formatting")
    func richTextFooterRoundTripsFormatting() throws {
        let attributed = NSMutableAttributedString(
            string: "Thanks — see you Monday.",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 14),
                         .foregroundColor: NSColor.systemRed]
        )
        attributed.append(NSAttributedString(
            string: "\n— Alex",
            attributes: [.font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 12), toHaveTrait: .italicFontMask)]
        ))

        let data = try #require(RichTextFooter.data(from: attributed))
        let roundtrip = try #require(RichTextFooter.attributed(from: data))
        #expect(roundtrip.string == attributed.string)

        let bold = roundtrip.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(bold?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test("Rich text footer round trips embedded image")
    func richTextFooterRoundTripsEmbeddedImage() throws {
        let rep = try #require(
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

        let data = try #require(RichTextFooter.data(from: attributed))
        let roundtrip = try #require(RichTextFooter.attributed(from: data))

        var attachmentCount = 0
        roundtrip.enumerateAttribute(.attachment, in: NSRange(location: 0, length: roundtrip.length)) { value, _, _ in
            if value is NSTextAttachment { attachmentCount += 1 }
        }
        #expect(attachmentCount >= 1, "RTFD round-trip must preserve the embedded image attachment")
        #expect(roundtrip.string.contains("from my desk"))
    }

    @Test("Write RTF includes plain and RTF")
    func writeRTFIncludesPlainAndRTF() throws {
        let attributed = NSAttributedString(
            string: "Onward.",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        let pb = NSPasteboard(name: NSPasteboard.Name("signoff.tests.rtf"))
        pb.clearContents()

        #expect(RichTextFooter.writeRTF(attributed, to: pb) == true)
        #expect(pb.string(forType: .string) == "Onward.")
        #expect(pb.data(forType: .rtf) != nil, "RTF representation must be written")
    }

    @Test("IsEmpty treats whitespace as unconfigured")
    func isEmptyTreatsWhitespaceAsUnconfigured() throws {
        let empty = try #require(RichTextFooter.data(from: NSAttributedString(string: "  \n ")))
        #expect(RichTextFooter.isEmpty(empty) == true)
        #expect(RichTextFooter.isEmpty(nil) == true)

        let real = try #require(RichTextFooter.data(from: NSAttributedString(string: "Thanks!")))
        #expect(RichTextFooter.isEmpty(real) == false)
    }
}