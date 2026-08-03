import SwiftUI
import SignoffCore

/// Signoff Design System — "Monochrome + Whisper"
///
/// A signature is personal. This system keeps the focus on content:
/// monochrome surfaces (cool-warm gray) with a single neutral accent and
/// per-bucket tonal tints that are applied sparingly — a 3-8% coloured
/// veil over translucent material, not an opaque paint coat.
///
/// Motion: spring-first, purposeful. Every transition has weight.
/// Materials: ultra-thin frosted glass (50 % translucency) with a tiny
/// calibrated bucket tint, so the popover reads as transparent but never
/// colorless. Everything is SF Symbol + text — no custom paths, no gradients.
public enum Brand {

    // MARK: - Brand Accent (Neutral)

    /// The one brand action accent — a restrained blue-gray. Used for primary
    /// buttons, selected state, the signature glyph. Never decorative.
    public static let ember = Palette.ember
    public static let emberBright = Palette.emberBright
    public static let emberDim = Palette.emberDim

    public static func ember(for scheme: ColorScheme) -> Color {
        scheme == .dark ? emberBright : ember
    }

    // MARK: - Layout & Rhythm

    public enum Layout {
        /// Base unit: 4pt. All spacing, radii, inset derive from this.
        public static let unit: CGFloat = 4
        public static let spacingXXS = unit * 1   // 4
        public static let spacingXS  = unit * 2   // 8
        public static let spacingS   = unit * 3   // 12
        public static let spacingM   = unit * 4   // 16
        public static let spacingL   = unit * 6   // 24
        public static let spacingXL  = unit * 8   // 32
        public static let spacing2XL = unit * 12  // 48

        /// Corner radius scale — continuous for optical correctness. Tightened
        /// to match macOS 26's flatter grouped-control radii; 14pt was a tell.
        public static let radiusXS   = unit * 1.5  // 6
        public static let radiusS    = unit * 2    // 8
        public static let radiusM    = unit * 2.5  // 10
        public static let radiusL    = unit * 3.5  // 14
        public static let radiusXL   = unit * 5    // 20
        public static let radiusPill = 999.0

        /// Hairline — 0.5pt @1x, 0.75pt @2x (retina-aware)
        public static let hairline: CGFloat = 0.5
        public static let borderWeight: CGFloat = 1.0

        /// Max content width for readability
        public static let maxContentWidth: CGFloat = 560
    }

    // MARK: - Motion Choreography

    public enum Motion {
        /// Primary spring — UI responds with weight.
        /// Gated by Reduce Motion: resolves to nil when accessibilityReduceMotion is active.
        public static let springPrimary   = Animation.spring(response: 0.45, dampingFraction: 0.82, blendDuration: 0)
        /// Quick spring — micro interactions.
        public static let springQuick     = Animation.spring(response: 0.28, dampingFraction: 0.88, blendDuration: 0)
        /// Gentle spring — content entrance.
        public static let springGentle    = Animation.spring(response: 0.55, dampingFraction: 0.85, blendDuration: 0)
        /// Expressive spring — celebratory moments.
        public static let springExpressive = Animation.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0)

        /// Ease for fades / cross-fades
        public static let easeOut    = Animation.easeOut(duration: 0.2)
        public static let easeInOut  = Animation.easeInOut(duration: 0.3)
        public static let easeSlow   = Animation.easeOut(duration: 0.5)

        /// Stagger delay between sibling elements
        public static let staggerDelay: Double = 0.06

        /// Shimmer sweep duration
        public static let shimmerDuration: Double = 1.4

        /// Returns a motion-safe animation for a spring. When Reduce Motion is
        /// enabled, replaces springs and x/y/z translations with a simple fade
        /// to avoid triggering vestibular discomfort (per HIG Accessibility).
        public static func safe(
            _ animation: Animation,
            reduceMotion: Bool
        ) -> Animation {
            if reduceMotion {
                return .easeOut(duration: 0.2)
            }
            return animation
        }
    }

    // MARK: - Surfaces (Monochrome Grayscale)

    /// Monochrome gray range. Page = near-white (light) / near-black (dark).
    /// Cards sit slightly lighter. No warm/brown tint — the per-bucket accent
    /// enters only through the ultraThin material overlay in the popover body.
    public enum Surface {
        public static func page(for scheme: ColorScheme) -> Color {
            scheme == .dark ? grayDark.page : grayLight.page
        }

        public static func card(for scheme: ColorScheme) -> Color {
            scheme == .dark ? grayDark.card : grayLight.card
        }

        public static func raised(for scheme: ColorScheme) -> Color {
            scheme == .dark ? grayDark.raised : grayLight.raised
        }

        public static func floating(for scheme: ColorScheme) -> Color {
            scheme == .dark ? grayDark.floating : grayLight.floating
        }

        public static func tint(for scheme: ColorScheme, opacity: Double = 0.06) -> Color {
            ember(for: scheme).opacity(opacity)
        }

        public static func divider(for scheme: ColorScheme) -> Color {
            scheme == .dark ? grayDark.divider : grayLight.divider
        }

        // Light palette — cool-neutral grays
        private enum grayLight {
            static let page     = Color(red: 0.969, green: 0.965, blue: 0.961)  // #F7F6F5
            static let card     = Color(red: 0.988, green: 0.986, blue: 0.983)  // #FCFBFB
            static let raised   = Color(red: 0.996, green: 0.994, blue: 0.992)
            static let floating = Color(red: 0.998, green: 0.997, blue: 0.996)
            static let divider  = Color(red: 0.760, green: 0.755, blue: 0.745).opacity(0.12)
        }

        // Dark palette — deep cool-dark
        private enum grayDark {
            static let page     = Color(red: 0.098, green: 0.100, blue: 0.102)  // #191A1A
            static let card     = Color(red: 0.140, green: 0.142, blue: 0.145)
            static let raised   = Color(red: 0.160, green: 0.163, blue: 0.167)
            static let floating = Color(red: 0.178, green: 0.181, blue: 0.185)
            static let divider  = Color(red: 0.330, green: 0.335, blue: 0.340).opacity(0.16)
        }
    }

    // MARK: - Text Neutrals

    /// Neutral gray text ramp — meets WCAG AA.
    public enum Ink {
        public static func primary(for scheme: ColorScheme) -> Color {
            scheme == .dark  ? Color(red: 0.945, green: 0.943, blue: 0.940)
                             : Color(red: 0.125, green: 0.128, blue: 0.132)
        }
        public static func secondary(for scheme: ColorScheme) -> Color {
            scheme == .dark  ? Color(red: 0.835, green: 0.830, blue: 0.822)
                             : Color(red: 0.245, green: 0.248, blue: 0.255)
        }
        public static func tertiary(for scheme: ColorScheme) -> Color {
            scheme == .dark  ? Color(red: 0.720, green: 0.717, blue: 0.708)
                             : Color(red: 0.370, green: 0.374, blue: 0.382)
        }
        public static func disabled(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.38) : Color.black.opacity(0.38)
        }
        public static func link(for scheme: ColorScheme) -> Color {
            ember(for: scheme)
        }
        public static func inverse(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Surface.page(for: .light) : Surface.page(for: .dark)
        }
    }

    // MARK: - Shadow System (Depth)

    /// Shadow tokens are MainActor-isolated because they contain SwiftUI `Color`
    /// which is not Sendable. All access happens on the main actor in SwiftUI views.
    @MainActor
    public enum Shadow {
        /// Card resting on page
        public static let card = ShadowToken(
            color: Color.black.opacity(0.12),
            radius: 12, x: 0, y: 6,
            spread: -2
        )
        /// Raised surface
        public static let raised = ShadowToken(
            color: Color.black.opacity(0.18),
            radius: 20, x: 0, y: 10,
            spread: -4
        )
        /// Floating peak
        public static let floating = ShadowToken(
            color: Color.black.opacity(0.24),
            radius: 28, x: 0, y: 14,
            spread: -6
        )
        /// Inner glow for focus / active
        public static let innerGlow = ShadowToken(
            color: Color.black.opacity(0.06),
            radius: 2, x: 0, y: 0,
            spread: 0
        )

        public struct ShadowToken {
            let color: Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
            let spread: CGFloat
        }
    }

    // MARK: - Typography Scale

    /// Consistent type scale across the app using system fonts with Dynamic Type support.
    /// Serif reserved for extended reading (signoff output).
    public enum Typography {
        /// Large display text (onboarding headlines)
        public static let display = Font.system(.title, design: .rounded).weight(.semibold)
        /// Section headlines
        public static let headline = Font.system(.headline, design: .rounded).weight(.semibold)
        /// Body text
        public static let body = Font.system(.body)
        /// Callout text
        public static let callout = Font.system(.callout)
        /// Footnote text
        public static let footnote = Font.system(.footnote)
        /// Caption 1
        public static let caption1 = Font.system(.caption)
        /// Caption 2
        public static let caption2 = Font.system(.caption2)
        /// Signoff output — serif for extended reading
        public static let signoff = Font.system(.body, design: .serif).weight(.regular)
        /// Monospace for codes/shortcuts
        public static let mono = Font.system(.footnote, design: .monospaced)
    }

    // MARK: - Bucket Tonal Accents (Ink Shades)

    /// Each bucket gets a tonal accent — like different inks from the same bottle.
    /// Readable on both schemes. Never "UI colors."
    public static func accent(for bucketId: String, scheme: ColorScheme) -> Color {
        guard let id = BucketID(rawValue: bucketId) else { return ember(for: scheme) }
        switch id {
        case .standard:     return scheme == .dark ? standardDark  : standardLight   // Dependable ink
        case .professional: return scheme == .dark ? profDark     : profLight      // Measured indigo
        case .unhinged:     return scheme == .dark ? unhDark      : unhLight       // Chaotic rust
        case .custom:       return ember(for: scheme)                              // Brand ember
        case .list:         return scheme == .dark ? listDark     : listLight      // Collected sage
        case .footer:       return scheme == .dark ? footerDark   : footerLight    // Formal slate
        case .generalLegacy:return ember(for: scheme)
        }
    }

    private static let standardLight  = Color(red: 0.220, green: 0.280, blue: 0.520)
    private static let standardDark   = Color(red: 0.580, green: 0.680, blue: 0.920)
    private static let profLight      = Color(red: 0.180, green: 0.260, blue: 0.580)
    private static let profDark       = Color(red: 0.540, green: 0.620, blue: 0.900)
    private static let unhLight       = Color(red: 0.720, green: 0.280, blue: 0.120)
    private static let unhDark        = Color(red: 0.930, green: 0.520, blue: 0.320)
    private static let listLight      = Color(red: 0.180, green: 0.460, blue: 0.260)
    private static let listDark       = Color(red: 0.440, green: 0.760, blue: 0.500)
    private static let footerLight    = Color(red: 0.240, green: 0.320, blue: 0.440)
    private static let footerDark     = Color(red: 0.500, green: 0.600, blue: 0.780)

    // MARK: - Palette (Private Raw Values)

    private enum Palette {
        // Neutral blue-gray accent — replaces the amber/brown ember.
        // Distinguished, restrained, reads well on both colour schemes
        // while staying out of the way of content.
        static let ember       = Color(red: 0.380, green: 0.440, blue: 0.520)  // #617085
        static let emberBright = Color(red: 0.560, green: 0.620, blue: 0.700)
        static let emberDim    = Color(red: 0.280, green: 0.320, blue: 0.400)
    }
}

// MARK: - View Extensions (Design System Application)

extension View {
    /// Apply card surface: brand fill + hairline + shadow. No system material —
    /// stacking `.regularMaterial` under a brand-tinted overlay produced a muddy
    /// glass-on-glass read. The brand card color is opaque and deliberate.
    func cardSurface(
        tint: Color? = nil,
        radius: CGFloat = Brand.Layout.radiusM,
        scheme: ColorScheme,
        elevated: Bool = false
    ) -> some View {
        let surfaceColor = elevated ? Brand.Surface.raised(for: scheme) : Brand.Surface.card(for: scheme)
        let shadow = elevated ? Brand.Shadow.raised : Brand.Shadow.card
        return self
            .padding(Brand.Layout.spacingM)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tint ?? surfaceColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Brand.Surface.divider(for: scheme), lineWidth: Brand.Layout.hairline)
            )
            .shadow(
                color: shadow.color,
                radius: shadow.radius,
                x: shadow.x,
                y: shadow.y
            )
    }

    /// Inner glow for focus/active states
    func innerGlow(active: Bool, scheme: ColorScheme) -> some View {
        self.overlay(
            RoundedRectangle(cornerRadius: Brand.Layout.radiusS, style: .continuous)
                .stroke(
                    active ? Brand.ember(for: scheme) : Brand.Surface.divider(for: scheme),
                    lineWidth: active ? Brand.Layout.borderWeight : Brand.Layout.hairline
                )
        )
    }

    /// Staggered entrance animation — respects Reduce Motion
    func staggeredEntrance(
        index: Int,
        delay: Double = Brand.Motion.staggerDelay,
        animation: Animation = Brand.Motion.springGentle,
        reduceMotion: Bool = false
    ) -> some View {
        let safeAnimation = Brand.Motion.safe(animation, reduceMotion: reduceMotion)
        return self
            .opacity(0)
            .offset(y: reduceMotion ? 0 : 16)
            .animation(safeAnimation.delay(delay * Double(index)), value: index)
            .onAppear {
                withAnimation(safeAnimation.delay(delay * Double(index))) {
                    // Trigger handled by view state
                }
            }
    }
}

// MARK: - Color Scheme Environment Helper

extension ColorScheme {
    var isDark: Bool { self == .dark }
}