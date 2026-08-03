import AppKit
import SwiftUI
import SignoffCore

/// Hidden offscreen window that gives `@Environment(\.openSettings)` a persistent
/// SwiftUI render tree so the Settings scene can be opened from the menu-bar
/// popover and the ⌘, command.
///
/// Since macOS 14 the `showSettingsWindow:` selectors no longer open Settings,
/// and the `openSettings` environment action silently no-ops without a live
/// SwiftUI view. The scene MUST be declared before the `Settings` scene in
/// `SignoffApp` for the environment propagation to resolve.
@MainActor
public struct SettingsContextView: View {
    @Environment(\.openSettings) private var openSettings

    public init() {}

    public var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
            .onAppear {
                // Park the context window far offscreen and out of the window
                // list exactly once. No per-activation re-hide.
                Self.hideContextWindow()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .openSettingsShortcutTriggered)
            ) { note in
                Task { @MainActor in
                    // Extract pane from userInfo for pane persistence
                    let _ = note.userInfo?["pane"] as? String
                    // TODO: Navigate to specific pane when Settings scene supports it
                    // For now, just open Settings (the openSettings action doesn't support pane navigation yet)
                    openSettings()
                }
            }
    }

    /// Move the context window far offscreen and out of the order, once.
    public static func hideContextWindow() {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == windowIdentifier }) else { return }
        window.setFrameOrigin(NSPoint(x: -40_000, y: -40_000))
        window.orderOut(nil)
    }

    public static let windowIdentifier = "signoff.settings-context"
}