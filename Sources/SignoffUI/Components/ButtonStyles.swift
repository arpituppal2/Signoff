import SwiftUI

/// All button styles are now system-native.
/// - Primary CTA → `.borderedProminent` (inherits accent color)
/// - Secondary   → `.bordered` / `.plain`
/// - Destructive → `Button(..., role: .destructive)` + `.bordered`
///
/// These aliases remain only for call sites that haven't been migrated.
public enum SignoffButtons {
    @available(*, deprecated, message: "Use .borderedProminent instead")
    public struct PrimaryStyle: ButtonStyle {
        public init() {}
        public func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.body.weight(.semibold))
                .frame(minHeight: 28)
        }
    }

    @available(*, deprecated, message: "Use .bordered or .plain instead")
    public struct GhostStyle: ButtonStyle {
        public init() {}
        public func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.body)
                .frame(minHeight: 28)
        }
    }
}

public extension ButtonStyle where Self == SignoffButtons.PrimaryStyle {
    @available(*, deprecated, message: "Use .borderedProminent instead")
    static var signoffPrimary: SignoffButtons.PrimaryStyle { .init() }
}
public extension ButtonStyle where Self == SignoffButtons.GhostStyle {
    @available(*, deprecated, message: "Use .bordered or .plain instead")
    static var signoffGhost: SignoffButtons.GhostStyle { .init() }
}
