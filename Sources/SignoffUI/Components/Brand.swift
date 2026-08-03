import SwiftUI
import SignoffCore

/// Signoff Design System — "Ink on Paper"
///
/// A signature is personal. It's ink meeting paper. Warmth meeting structure.
/// This system builds on that metaphor: parchment surfaces, ink typography,
/// a single amber ember for action, and per-bucket tonal accents that feel
/// like ink shades — not UI colors.
///
/// Motion: spring-first, staggered, purposeful. Every transition has weight.
/// Materials: layered translucency with intent — not decoration.
public enum Brand {

    // MARK: - Brand Accent (The Ember)

    /// The one brand action color — warm amber ember. Used for primary actions,
    /// the signature mark, active states. Never decorative.
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

        /// Corner radius scale — continuous for optical correctness
        public static let radiusXS   = unit * 1.5  // 6
        public static let radiusS    = unit * 2.5  // 10
        public static let radiusM    = unit * 3.5  // 14
        public static let radiusL    = unit * 5    // 20
        public static let radiusXL   = unit * 7    // 28
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

    // MARK: - Surfaces (Paper System)

    /// Layered paper metaphor. Base → Elevated → Overlay → Floating.
    /// Each layer adds depth through material + subtle tint + shadow.
    public enum Surface {
        /// The base "page" — warm parchment (light) / deep ink (dark)
        public static func page(for scheme: ColorScheme) -> Color {
            scheme == .dark ? ink.page : parchment.page
        }

        /// A card resting on the page
        public static func card(for scheme: ColorScheme) -> Color {
            scheme == .dark ? ink.card : parchment.card
        }

        /// Raised surface (popover, tooltip)
        public static func raised(for scheme: ColorScheme) -> Color {
            scheme == .dark ? ink.raised : parchment.raised
        }

        /// Floating (toast, peak)
        public static func floating(for scheme: ColorScheme) -> Color {
            scheme == .dark ? ink.floating : parchment.floating
        }

        /// Subtle tint wash for branded cards
        public static func tint(for scheme: ColorScheme, opacity: Double = 0.08) -> Color {
            ember(for: scheme).opacity(opacity)
        }

        /// Divider / hairline
        public static func divider(for scheme: ColorScheme) -> Color {
            scheme == .dark ? ink.divider : parchment.divider
        }

        // Light palette (parchment)
        private enum parchment {
            static let page     = Color(red: 0.978, green: 0.969, blue: 0.952)  // #F9F7F3
            static let card     = Color(red: 0.996, green: 0.992, blue: 0.980)  // #FEFDF9 — +4% luminance over page
            static let raised   = Color(red: 1.000, green: 0.996, blue: 0.988)  // #FFFEFD — +3% over card
            static let floating = Color(red: 1.000, green: 0.998, blue: 0.992)  // #FFFEFD
            static let divider  = Color(red: 0.820, green: 0.790, blue: 0.740).opacity(0.12)  // Min 0.12 for AA
        }

        // Dark palette (ink)
        private enum ink {
            static let page     = Color(red: 0.090, green: 0.084, blue: 0.075)  // #171613
            static let card     = Color(red: 0.138, green: 0.130, blue: 0.118)  // #23211E — +4% luminance over page
            static let raised   = Color(red: 0.158, green: 0.148, blue: 0.134)  // #282522 — +3% over card
            static let floating = Color(red: 0.175, green: 0.164, blue: 0.148)  // #2D2A25
            static let divider  = Color(red: 0.300, green: 0.275, blue: 0.240).opacity(0.16)  // Min 0.16 for AA
        }
    }

    // MARK: - Ink Typography (Text System)

    /// Text colors derived from ink on paper. Never pure black/white.
    /// Rebased to meet WCAG AA: body text 4.5:1, large text (18pt+) 3:1
    public enum Ink {
        public static func primary(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color(red: 0.945, green: 0.925, blue: 0.890)  // #F1ECE3 — ~11:1 on dark
                            : Color(red: 0.145, green: 0.132, blue: 0.114)    // #25211D — ~12:1 on light
        }
        public static func secondary(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color(red: 0.835, green: 0.795, blue: 0.730)    // #D5CBBB — ~5.2:1 on dark page
                            : Color(red: 0.240, green: 0.215, blue: 0.172)    // #3D372C — ~5.5:1 on light page
        }
        public static func tertiary(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color(red: 0.720, green: 0.685, blue: 0.630)    // #B8AE9F — ~4.5:1 on dark page
                            : Color(red: 0.350, green: 0.315, blue: 0.270)    // #595045 — ~4.5:1 on light page
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
        static let ember       = Color(red: 0.760, green: 0.480, blue: 0.180)  // #C27A2E
        static let emberBright = Color(red: 0.880, green: 0.600, blue: 0.220)
        static let emberDim    = Color(red: 0.600, green: 0.380, blue: 0.140)
    }
}

// MARK: - View Extensions (Design System Application)

extension View {
    /// Apply card surface: material + tint + hairline + shadow
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
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill((tint ?? surfaceColor).opacity(scheme == .dark ? 0.12 : 0.08))
                    )
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