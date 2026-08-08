import AppKit

/// An `NSTextAttachment` that keeps its source image and renders at a chosen
/// display size, so inserted images can be (a) auto-fit to a sensible width on
/// drop instead of appearing at natural pixel size, and (b) resized afterward
/// via a context menu (Small / Medium / Large / Actual). The original image is
/// retained so resizing re-renders crisply rather than scaling a downscaled copy.
final class ScalableImageAttachment: NSTextAttachment {
    let originalImage: NSImage
    var displaySize: NSSize

    init(image: NSImage, displaySize: NSSize) {
        self.originalImage = image
        self.displaySize = displaySize
        super.init(data: nil, ofType: nil)
        self.image = ScalableImageAttachment.render(originalImage, at: displaySize)
    }

    required init?(coder: NSCoder) { fatalError("ScalableImageAttachment is not NSCoding-archivable") }

    override func attachmentBounds(for textContainer: NSTextContainer?,
                                   proposedLineFragment lineFrag: CGRect,
                                   glyphPosition position: CGPoint,
                                   characterIndex charIndex: Int) -> CGRect {
        return CGRect(origin: .zero, size: displaySize)
    }

    func setDisplaySize(_ size: NSSize) {
        displaySize = size
        image = ScalableImageAttachment.render(originalImage, at: size)
    }

    /// Scale relative to the original image's natural size (0 < scale ≤ 1).
    func setScale(_ scale: CGFloat) {
        let nat = originalImage.size
        let s = max(min(scale, 1.0), 0.05)
        setDisplaySize(NSSize(width: nat.width * s, height: nat.height * s))
    }

    static func fit(image: NSImage, maxWidth: CGFloat) -> NSSize {
        let nat = image.size
        guard nat.width > 0, nat.height > 0 else { return nat }
        let cap: CGFloat = max(maxWidth, 1)
        if nat.width <= cap { return nat }
        let ratio = cap / nat.width
        return NSSize(width: cap, height: nat.height * ratio)
    }

    private static func render(_ original: NSImage, at size: NSSize) -> NSImage {
        guard size.width > 0, size.height > 0 else { return original }
        let rep = NSImage(size: size, flipped: false) { dst in
            original.draw(in: dst,
                          from: .zero,
                          operation: .copy,
                          fraction: 1.0)
            return true
        }
        return rep
    }
}
