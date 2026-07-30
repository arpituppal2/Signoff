import AppKit

/// Regular ↔ accessory activation for an LSUIElement menu-bar app.
///
/// With `LSUIElement = YES`, the process starts as an accessory (no Dock icon).
/// Windows (Settings / About / Help) can end up buried unless we briefly flip to
/// `.regular`, activate, then return to `.accessory` once those windows close.
@MainActor
enum AppActivation {
    /// Bring Signoff forward so a window (Settings / About / Help) is not buried.
    static func forForegroundWindow() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Return to accessory (no Dock icon) when no keyable app windows remain.
    /// Ignores status-item / popover host windows that cannot become key.
    static func returnToAccessoryIfAppropriate() {
        let hasVisibleKeyableWindow = NSApp.windows.contains { window in
            window.isVisible
                && window.canBecomeKey
                && window.styleMask.contains(.titled)
        }
        guard !hasVisibleKeyableWindow else { return }
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
