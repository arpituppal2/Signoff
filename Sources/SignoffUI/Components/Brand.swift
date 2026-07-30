import SwiftUI
import SignoffCore

/// Signoff's design system.
///
/// Concept: a signoff is a signature — ink on paper. The brand palette is
/// built around that: warm parchment + ink in light, deep ink + amber ember
/// in dark. A single brand accent (amber) anchors the signature mark and the
/// generate action; each bucket carries its own tonal accent so tone is felt
/// at a glance without becoming a rainbow.
///
/// Everything still respects system semantics — these tokens compose on top
/// of SwiftUI dynamic type, Dark Mode, Increase Contrast, and Reduce
/// Transparency. Colors are tuned per `ColorScheme`; high-contrast falls
/// back toward system labels.
public enum Brand {

    // MARK: - Brand accent

    /// Signature amber — the brand's one warm accent. Used on the mark, the
    /// primary Generate action, and the active bucket row.
    public static let amber = Palette.amber
    /// Lighter amber for dark-mode rendering on dark surfaces.
    public static let amberBright = Palette.amberBright
    /// The amber most readable on the current scheme.
    public static func amber(for scheme: ColorScheme) -> Color {
        scheme == .dark ? amberBright : amber
    }

    // MARK: - Layout

    public enum Layout {
        /// Card / surface corner radius.
        public static let cornerRadius: CGFloat = 10
        /// Tighter radius for controls, chips, and inline pills.
        public static let controlCornerRadius: CGFloat = 7
        /// Hairline stroke weight for outlined surfaces.
        public static let hairline: CGFloat = 0.75
    }

    // MARK: - Surfaces

    /// Paper / ink-aware surface fills. Never use raw `Color.white`/`.black`
    /// in the UI — go through these so the whole surface system shifts as one.
    public enum Semantic {
        /// The popover's base "paper" fill.
        public static func surfaceBase(for scheme: ColorScheme) -> Color {
            scheme == .dark ? ink.deep : cream.paper
        }
        /// A raised card sitting on the paper.
        public static func surfaceElevated(for scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color.white.opacity(0.055)
                : Color.black.opacity(0.030)
        }
        /// Hover/active fill for rows.
        public static func surfaceHover(for scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color.white.opacity(0.08)
                : ink.opacity(0.045)
        }
        /// Selected-row wash (uses brand amber, kept subtle).
        public static func surfaceSelected(for scheme: ColorScheme) -> Color {
            amber(for: scheme).opacity(scheme == .dark ? 0.16 : 0.12)
        }

        public static func textPrimary(for scheme: ColorScheme) -> Color {
            scheme == .dark ? cream.subtle : ink.base
        }
        public static func textSecondary(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.62) : ink.secondary
        }
        public static func textTertiary(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.40) : ink.tertiary
        }
        public static func divider(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.10) : ink.opacity(0.10)
        }
    }

    // MARK: - Bucket accents

    /// A tonal accent per bucket — readable, distinct, never clownish.
    public static func accent(for bucketId: String, scheme: ColorScheme) -> Color {
        guard let id = BucketID(rawValue: bucketId) else { return amber(for: scheme) }
        switch id {
        case .standard:     return ink.accent(scheme)      // dependable ink
        case .professional:  return indigo.accent(scheme)   // measured, official
        case .unhinged:      return flame.accent(scheme)    // chaotic warm
        case .custom:        return amber(for: scheme)      // brand amber
        case .list:          return sage.accent(scheme)     // collected calm
        case .footer:        return slate.accent(scheme)    // signed, formal
        case .generalLegacy: return amber(for: scheme)
        }
    }

    // MARK: - Color group (private)

    /// Warm parchment (light) — the "paper".
    private enum cream {
        static let paper   = Color(red: 0.982, green: 0.976, blue: 0.965)
        static let subtle  = Color(red: 0.149, green: 0.137, blue: 0.118)
    }

    /// Ink (dark) — the writing surface + ink names.
    private enum ink {
        static let base      = Color(red: 0.118, green: 0.110, blue: 0.098)
        static let deep      = Color(red: 0.094, green: 0.088, blue: 0.078)
        static let secondary = Color(red: 0.349, green: 0.322, blue: 0.278)
        static let tertiary  = Color(red: 0.553, green: 0.522, blue: 0.463)

        static func opacity(_ a: Double) -> Color { base.opacity(a) }
        static func accent(_ s: ColorScheme) -> Color {
            // dependable ink-leaning brand color; stays readable on both schemes
            s == .dark ? Color(red: 0.902, green: 0.780, blue: 0.435) : Color(red: 0.525, green: 0.396, blue: 0.149)
        }
    }

    /// Per-bucket accent helpers (each readable on both schemes).
    private enum indigo {
        static func accent(_ s: ColorScheme) -> Color {
            s == .dark ? Color(red: 0.620, green: 0.659, blue: 0.937)
                       : Color(red: 0.282, green: 0.337, blue: 0.682)
        }
    }
    private enum flame {
        static func accent(_ s: ColorScheme) -> Color {
            s == .dark ? Color(red: 0.949, green: 0.510, blue: 0.298)
                       : Color(red: 0.796, green: 0.314, blue: 0.098)
        }
    }
    private enum sage {
        static func accent(_ s: ColorScheme) -> Color {
            s == .dark ? Color(red: 0.498, green: 0.776, blue: 0.541)
                       : Color(red: 0.231, green: 0.498, blue: 0.278)
        }
    }
    private enum slate {
        static func accent(_ s: ColorScheme) -> Color {
            s == .dark ? Color(red: 0.541, green: 0.612, blue: 0.737)
                       : Color(red: 0.290, green: 0.376, blue: 0.482)
        }
    }
}
