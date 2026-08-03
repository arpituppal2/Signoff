import AppKit

/// Opens the SwiftUI `Settings` scene from AppKit call sites that lack
/// `@Environment(\.openSettings)`.
///
/// The `showSettingsWindow:` / `showPreferencesWindow:` selectors were
/// deprecated in macOS 14 and no longer open the Settings scene, and the
/// `openSettings` environment action silently no-ops without a live SwiftUI
/// render tree. So this opener (a) flips to `.regular` + activates so the
/// window is not buried, then (b) routes through `SettingsContextWindow`'s
/// hidden scene, which owns `openSettings`.
///
/// Also the recovery path when `AppSettings.showsStatusItem` is false
/// (HIG hide menu-bar extra): Dock-less LSUIElement stays; reopen / ⌘,
/// while frontmost still reach Settings via this opener.
@MainActor
enum SettingsSceneOpener {
    private static var didInstallCloseObserver = false
    /// Holds the will-close observer target. Selector-based observation avoids
    /// the block-observer `@Sendable` closure, so the main-actor-only
    /// `window.styleMask` read stays on the main actor with no warning.
    private static let closeObserver = WindowCloseObserver()

    static func open() {
        installCloseObserverIfNeeded()
        AppActivation.forForegroundWindow()
        // The hidden SettingsContextWindow scene observes this and calls the
        // live `openSettings` environment action, then brings the window
        // forward. SettingsView also observes it to switch to a requested pane.
        NotificationCenter.default.post(name: .openSettingsShortcutTriggered, object: nil)
    }

    private static func installCloseObserverIfNeeded() {
        guard !didInstallCloseObserver else { return }
        didInstallCloseObserver = true
        // AppKit delivers NSWindow.willClose on the main thread, satisfying the
        // @MainActor selector. Settings / About / Help are titled windows;
        // menu-bar extras have no title to return them past.
        NotificationCenter.default.addObserver(
            closeObserver,
            selector: #selector(WindowCloseObserver.windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }
}

/// Selector target for `NSWindow.willClose`. `@MainActor` so the
/// `styleMask` read (a main-actor-isolated AppKit property) is statically
/// on-actor — no `@Sendable` crossing, no data-race warning.
private final class WindowCloseObserver: NSObject {
    @MainActor @objc func windowWillClose(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        // Settings / About / Help are titled; menu-bar extras are not.
        guard window.styleMask.contains(.titled) else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            AppActivation.returnToAccessoryIfAppropriate()
        }
    }
}
