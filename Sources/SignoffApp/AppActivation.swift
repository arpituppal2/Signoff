import AppKit

/// Activation helpers for an LSUIElement menu-bar app that must never show a
/// Dock icon.
///
/// `LSUIElement = YES` starts the process as an accessory. To bring windows
/// (Settings / About / Help) forward we do NOT flip to `.regular` — that would
/// pop a Dock icon (the user explicitly wants Signoff out of the Dock). For an
/// accessory app, `NSApp.activate(ignoringOtherApps:)` brings the app and its
/// windows forward while keeping it Dock-less.
@MainActor
enum AppActivation {
    /// Bring Signoff forward so a window (Settings / About / Help) is not buried.
    static func forForegroundWindow() {
        NSApp.activate(ignoringOtherApps: true)
    }

    /// No-op kept for symmetry: the app stays `.accessory` permanently, so there
    /// is nothing to restore after a window closes.
    static func returnToAccessoryIfAppropriate() {}
}
