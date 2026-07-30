import AppKit

/// Opens the SwiftUI `Settings` scene from AppKit call sites that lack
/// `@Environment(\.openSettings)`.
///
/// Uses the selector SwiftUI registers for the Settings scene
/// (`showSettingsWindow:`) after activating with the regular ↔ accessory
/// pattern so the window is not buried under other apps.
///
/// Also the recovery path when `AppSettings.showsStatusItem` is false
/// (HIG hide menu-bar extra): Dock-less LSUIElement stays; reopen / ⌘,
/// while frontmost still reach Settings via this opener.
@MainActor
enum SettingsSceneOpener {
    private static var didInstallCloseObserver = false

    static func open() {
        installCloseObserverIfNeeded()
        AppActivation.forForegroundWindow()
        // SwiftUI Settings scene registers this action on NSApplication.
        // Prefer it over a hand-rolled NSWindow hosting SettingsView.
        let showSettings = Selector(("showSettingsWindow:"))
        if NSApp.sendAction(showSettings, to: nil, from: nil) {
            return
        }
        // Fallback for older selector naming (Preferences era).
        let showPrefs = Selector(("showPreferencesWindow:"))
        _ = NSApp.sendAction(showPrefs, to: nil, from: nil)
    }

    private static func installCloseObserverIfNeeded() {
        guard !didInstallCloseObserver else { return }
        didInstallCloseObserver = true
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let window = note.object as? NSWindow else { return }
            // Settings / About / Help are titled; status-item popovers are not.
            guard window.styleMask.contains(.titled) else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000)
                AppActivation.returnToAccessoryIfAppropriate()
            }
        }
    }
}
