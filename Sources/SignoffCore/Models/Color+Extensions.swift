import SwiftUI

/// Signoff's system typography tokens. Body/caption bind to SwiftUI text styles
/// so Dynamic Type works automatically. `display()` + `signature()` use the
/// rounded design for the wordmark and the signoff preview so the "handwritten
/// signature" idea reads without importing a custom font.
///
/// After the Brand consolidation, palette, spacing, and color extensions live
/// exclusively in `Sources/SignoffUI/Components/Brand.swift`. This file keeps
/// only the typography tokens that the full app stack may reference.
public enum SignoffFont {
    public static func display()   -> Font { .system(size: 48, weight: .semibold, design: .rounded) }
    public static func heading()   -> Font { .system(size: 20, weight: .semibold) }
    /// The signature preview font — rounded, lightly tracked, reads as a
    /// drafted signoff rather than raw mono code.
    public static func signature() -> Font {
        .system(.body, design: .rounded).weight(.medium)
    }
    public static func mono()      -> Font { .body.monospaced() }
}