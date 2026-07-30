import SwiftUI

/// Signoff's brand color primitives. The inks-and-parchment palette behind
/// `Brand` (in SignoffUI). System semantic colors (`Color.primary`,
/// `.secondary`, `.accentColor`, `.green`, `.orange`) are still used where a
/// view should follow the user's accent or status conventions — brand colors
/// are for surface identity and the signature mark, not for chrome overrides.
public enum Palette {
    /// Brand amber — the signature accent. Readable on both schemes.
    public static let amber       = Color(red: 0.525, green: 0.396, blue: 0.149)
    /// Bright amber — dark-mode expression of the accent.
    public static let amberBright = Color(red: 0.902, green: 0.780, blue: 0.435)
    /// Light-mode ink (deep warm near-black).
    public static let ink         = Color(red: 0.118, green: 0.110, blue: 0.098)
    /// Light-mode parchment paper.
    public static let paper       = Color(red: 0.982, green: 0.976, blue: 0.965)

    @available(*, deprecated, renamed: "amberBright")
    public static var amberDark: Color { amberBright }
}

public extension Color {
    /// Brand amber.
    static var signoffAmber: Color { Palette.amber }

    /// Resolves to the brand amber best readable on the given scheme.
    static func signoffAmber(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Palette.amberBright : Palette.amber
    }

    static func surfaceBase(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Palette.ink : Palette.paper
    }
    static func textPrimary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Palette.paper : Palette.ink
    }
    static func textSecondary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.62) : Color(white: 0.30)
    }
}

/// System spacing constants. Prefer native padding values (8, 10, 12, 16, 20).
public enum Spacing {
    public static let xs:  CGFloat = 4
    public static let sm:  CGFloat = 8
    public static let md:  CGFloat = 12
    public static let lg:  CGFloat = 16
    public static let xl:  CGFloat = 24
}

/// Typography tokens. Body/caption bind to SwiftUI text styles so Dynamic
/// Type works. `display()` + `signature()` are the only bespoke faces — both
/// use the rounded design for the wordmark and the signoff preview so the
/// "handwritten signature" idea reads without importing a custom font.
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
