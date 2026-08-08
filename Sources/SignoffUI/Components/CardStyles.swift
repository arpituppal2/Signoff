import SwiftUI
import SignoffCore

/// Reusable visual styles for surfaces layered on the popover base.
/// Flat elevated fills only — no drop shadows or materials inside NSPopover chrome.
public enum CardStyles {
    public struct StatusLineStyle: ViewModifier {
        public init() {}
        public func body(content: Content) -> some View {
            content
                .padding(.horizontal, Brand.Layout.spacingS)
                .padding(.vertical, Brand.Layout.spacingXXS)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Brand.Layout.radiusXS)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
        }
    }
}

public extension View {
    func statusLine() -> some View { modifier(CardStyles.StatusLineStyle()) }
}

/// The signature preview card shown after a successful generation.
/// A drafted signoff on paper — monospace signature type. A small inline copy
/// icon sits in the corner: tap it to recopy the signoff; it morphs into a
/// checkmark with a spring, then morphs back.
public struct SignatureCardView: View {
    public let text: String
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.system(size: 15, weight: .regular, design: .monospaced))
                .kerning(0.5)
                .foregroundStyle(Brand.Ink.primary(for: scheme))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Brand.Layout.spacingM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Brand.Layout.radiusM, style: .continuous)
                .fill(Brand.Surface.raised(for: scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Brand.Layout.radiusM, style: .continuous)
                .stroke(Brand.Surface.divider(for: scheme), lineWidth: Brand.Layout.hairline)
        )
        .overlay(alignment: .topTrailing) {
            Button {
                copySignoff()
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(copied ? Brand.ember(for: scheme) : Brand.Ink.tertiary(for: scheme))
                    .frame(width: 24, height: 24)
                    .contentTransition(.symbolEffect(.replace))
                    .scaleEffect(copied ? 1.15 : 1.0)
                    .animation(
                        Brand.Motion.safe(.spring(response: 0.32, dampingFraction: 0.6), reduceMotion: reduceMotion),
                        value: copied
                    )
            }
            .buttonStyle(.borderless)
            .padding(Brand.Layout.spacingXS)
            .help(copied ? "Copied" : "Copy signoff")
            .accessibilityLabel(copied ? "Copied" : "Copy signoff")
        }
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        "Generated signoff: \(text)"
    }

    private func copySignoff() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        Task { @MainActor in
            await SystemSoundClient.shared.play(.tink)
        }
        withAnimation(Brand.Motion.safe(.easeOut(duration: 0.2), reduceMotion: reduceMotion)) {
            copied = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(Brand.Motion.safe(.easeOut(duration: 0.2), reduceMotion: reduceMotion)) {
                copied = false
            }
        }
    }
}

/// Privacy badge — lock + "100% private", tinted by caller. Signals the
/// on-device promise at a glance without being loud.
public struct PrivacyBadge: View {
    @Environment(\.colorScheme) private var scheme
    public init() {}
    public var body: some View {
        Label("100% private", systemImage: "lock.fill")
            .font(.caption2.weight(.medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Brand.ember(for: scheme))
            .accessibilityLabel("100 percent private. All generation stays on your Mac.")
    }
}
