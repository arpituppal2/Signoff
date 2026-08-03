import AppKit
import SwiftUI
import SignoffCore
import SignoffUI

/// Hidden 1×1 window that gives `@Environment(\.openSettings)` a persistent
/// SwiftUI render tree so the Settings scene can be opened from the menu-bar
/// popover.
///
/// Since macOS 14 the `showSettingsWindow:` selectors no longer open Settings,
/// and the `openSettings` environment action silently no-ops without a live
/// SwiftUI view. The scene MUST be declared before the `Settings` scene in
/// `SignoffApp` for the environment propagation to resolve.
///
/// The window is kept tiny and titled-but-hidden so it is imperceptible, yet
/// stays alive for the app's lifetime. `AppActivation` ignores it by
/// identifier so it never blocks the accessory ↔ regular transition.
@MainActor
struct SettingsContextView: View {
    /// Key must match `SettingsView`'s `@AppStorage("signoff.settings.lastPane")`.
    private static let lastPaneKey = "signoff.settings.lastPane"
    fileprivate static let windowIdentifier = "signoff.settings-context"

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
            .onAppear {
                Self.installHideObserverIfNeeded()
                Task { @MainActor in Self.hideContextWindow() }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .openSettingsShortcutTriggered)
            ) { note in
                // Persist a requested pane so SettingsView applies it on appear,
                // even when the window is opened for the first time.
                if let pane = note.object as? SettingsPane {
                    UserDefaults.standard.set(pane.rawValue, forKey: Self.lastPaneKey)
                }
                Task { @MainActor in
                    openSettingsFromContext()
                }
            }
    }

    /// Activate then present. The delay lets the activation policy flip settle;
    /// `orderFrontRegardless` covers cases where the window lands behind another app.
    private func openSettingsFromContext() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            if let window = Self.settingsWindow() {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }

    private static func settingsWindow() -> NSWindow? {
        NSApp.windows.first { window in
            guard window.styleMask.contains(.titled) else { return false }
            return window.title.localizedCaseInsensitiveContains("settings")
                || window.title.localizedCaseInsensitiveContains("preferences")
        }
    }
}

/// Orders the hidden settings-context window out on every app activation so it
/// never surfaces as a 1pt sliver. Selector-based observation avoids the
/// block-observer `@Sendable` closure crossing the main actor.
private final class SettingsContextWindowHider: NSObject {
    @MainActor @objc func appDidBecomeActive(_ note: Notification) {
        SettingsContextView.hideContextWindow()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            SettingsContextView.hideContextWindow()
        }
    }
}

@MainActor
private extension SettingsContextView {
    static var didInstallHideObserver = false

    static func installHideObserverIfNeeded() {
        guard !didInstallHideObserver else { return }
        didInstallHideObserver = true
        NotificationCenter.default.addObserver(
            windowHider,
            selector: #selector(SettingsContextWindowHider.appDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    static func hideContextWindow() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == windowIdentifier }) else { return }
        window.setFrameOrigin(NSPoint(x: -40_000, y: -40_000))
        window.orderOut(nil)
    }

    static let windowHider = SettingsContextWindowHider()
}
