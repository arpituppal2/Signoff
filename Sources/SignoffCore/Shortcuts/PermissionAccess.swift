import Foundation
import CoreGraphics
import AppKit

/// Input Monitoring permission probe for global event taps (`CGEvent.tapCreate`).
/// Distinct from Accessibility (`AXIsProcessTrusted`), which is required for
/// synthesizing paste (⌘V) into other apps.
public enum InputMonitoringAccess {
    public static let systemSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!

    /// `true` when the process may already listen for events (no prompt).
    public static func isGranted() -> Bool {
        CGPreflightListenEventAccess()
    }

    /// Requests Input Monitoring if not already granted. May return `true`
    /// after presenting the system prompt before the user has decided —
    /// callers should re-check `isGranted()` after the user returns.
    @discardableResult
    public static func request() -> Bool {
        if CGPreflightListenEventAccess() { return true }
        return CGRequestListenEventAccess()
    }

    public static func openSystemSettings() {
        NSWorkspace.shared.open(systemSettingsURL)
    }
}

/// Accessibility privacy pane deep link (paste / AX automation).
public enum AccessibilityAccess {
    public static let systemSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    public static func openSystemSettings() {
        NSWorkspace.shared.open(systemSettingsURL)
    }
}
