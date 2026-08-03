import AppKit
import Foundation

/// Reliable Settings opener for an LSUIElement (menu-bar only) app.
///
/// macOS 14+ deprecated `showSettingsWindow:` / `showPreferencesWindow:`.
/// The SwiftUI `Settings` scene can be opened via `@Environment(\.openSettings)`
/// but that requires a live SwiftUI view hierarchy. In a MenuBarExtra popover
/// the environment action silently no-ops.
///
/// Strategy: Post `.openSettingsShortcutTriggered` notification which is received
/// by `SettingsContextView` (hidden 1×1 window with `@Environment(\.openSettings)`).
/// Pass pane in `userInfo` for pane persistence.
@MainActor
public enum SettingsOpener {
    private static var didInstallObserver = false
    private static let closeObserver = WindowCloseObserver()

    public static func open(pane: String? = nil) {
        // Activate the app (LSUIElement stays Dock-less)
        NSApp.activate(ignoringOtherApps: true)

        // Install the centering observer once
        installCenteringObserverIfNeeded()

        // Post notification -> SettingsContextView receives -> calls openSettings()
        var userInfo: [AnyHashable: Any] = [:]
        if let pane { userInfo["pane"] = pane }
        NotificationCenter.default.post(name: .openSettingsShortcutTriggered, object: nil, userInfo: userInfo)
    }

    private static func installCenteringObserverIfNeeded() {
        guard !didInstallObserver else { return }
        didInstallObserver = true

        NotificationCenter.default.addObserver(
            closeObserver,
            selector: #selector(WindowCloseObserver.windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }
}

/// Selector target for `NSWindow.didBecomeKey`. `@MainActor` so the
/// `styleMask` and `title` reads (main-actor-isolated AppKit properties) are
/// statically on-actor — no `@Sendable` crossing, no data-race warning.
@MainActor
public final class WindowCloseObserver: NSObject {
    @objc public func windowDidBecomeKey(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        // We're on the main actor now
        guard window.styleMask.contains(.titled),
              ["General", "Shortcuts", "Privacy", "Advanced"].contains(window.title) else { return }

        // Center the Settings window on the active screen
        window.center()
    }
}