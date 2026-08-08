import AppKit
import SwiftUI
import SignoffCore

/// A tiny borderless, non-activating panel that floats a drawing `signature`
/// SF Symbol at a screen rect (resolved by `CaretLocator` from the focused
/// text field's caret). Shown when a global generate shortcut fires so the
/// user sees a beat of feedback exactly where they're typing — animation on,
/// then off, ideally just before the paste lands.
@MainActor
public final class SignatureOverlayWindow {
    public static let shared = SignatureOverlayWindow()

    private var panel: NSPanel?
    private var workItem: DispatchWorkItem?

    private init() {}

    /// Show the signature over `rect` (AppKit screen coords) for `duration`,
    /// then fade out and remove. No-op (and cleans up) if `rect` is nil — the
    /// caller skips animation when the caret position can't be resolved.
    public func show(at rect: NSRect?, duration: TimeInterval = 0.9) {
        guard let rect else { dismiss(); return }

        // Respect Reduce Motion: skip the overlay entirely.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return
        }

        let symbolSize: CGFloat = 52
        let panel = NSPanel(contentRect: NSRect(x: rect.midX - symbolSize,
                                                y: rect.maxY + 6,
                                                width: symbolSize * 2,
                                                height: symbolSize * 1.6),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isMovable = false
        panel.contentView = NSHostingView(rootView: SignatureOverlayView())
        panel.orderFrontRegardless()

        self.panel?.orderOut(nil)
        self.panel = panel

        // Fade out before the typical paste latency (~0.6–1.0s) completes,
        // so the symbol is gone by the time text appears.
        workItem?.cancel()
        let fade = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.dismiss()
            }
        }
        workItem = fade
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: fade)
    }

    public func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        workItem?.cancel()
        workItem = nil
    }
}

private struct SignatureOverlayView: View {
    @State private var phase: Phase = .off

    enum Phase { case off, drawing, written, unwriting }

    /// Pen-stroke write/unwrite — no opacity fade. Symbol is fully present the
    /// moment it appears, the only motion is the ink being applied (and then
    /// erased) so the feedback reads as "writing, then sent".
    var body: some View {
        Image(systemName: "signature")
            .font(.system(size: 52, weight: .semibold))
            .foregroundStyle(.tint)
            .symbolEffect(.drawOn.individually, options: .speed(1.3), isActive: phase == .drawing || phase == .written)
            .symbolEffect(.drawOff.individually, options: .speed(1.3), isActive: phase == .unwriting)
            .onAppear {
                phase = .drawing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    phase = .written
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                    phase = .unwriting
                }
            }
    }
}
