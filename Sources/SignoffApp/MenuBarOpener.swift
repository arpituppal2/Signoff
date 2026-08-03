import AppKit
import SignoffCore

/// Programmatically toggles the SwiftUI `MenuBarExtra` popover.
///
/// SwiftUI's `MenuBarExtra` (`.window` style) exposes no public API to open its
/// popover from code. The reliable approach is to locate the `NSStatusItem`
/// SwiftUI created and send a click to its button. The item list is reached via
/// KVC on `NSStatusBar` (private, but stable across current macOS releases and
/// fine for an ad-hoc signed app). Wired from the ⌃⌘` Carbon shortcut.
@MainActor
enum MenuBarOpener {
    private static var lastKnownButton: NSStatusBarButton?

    /// Toggle the menu bar popover. Falls back to the last known button when
    /// the status bar query fails.
    static func toggle() {
        let button = findStatusItemButton() ?? lastKnownButton
        guard let button else { return }
        lastKnownButton = button
        button.performClick(nil)
    }

    private static func findStatusItemButton() -> NSStatusBarButton? {
        let statusBar = NSStatusBar.system
        guard let items = statusBar.value(forKey: "statusItems") as? [NSStatusItem],
              let button = items.first(where: { $0.button != nil })?.button else {
            return nil
        }
        return button
    }
}
