import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

/// Throws from `PasteAutomation.paste(_:)` — every case maps to a concrete
/// actionable UI message in `AppState.generateNow()`. `Sendable` because they
/// fly across `Task @MainActor` boundaries in the calling pipeline.
/// File-scope (not nested) so `AppState`'s `catch PasteError.accessibilityDenied`
/// keeps its existing unqualified reference.
public enum PasteError: Error, Sendable, Equatable {
    /// Pasteboard refused the string write — usually means another app holds
    /// the pasteboard with a lock (rare; typically a clipboard manager).
    case pasteboardWriteFailed
    /// Accessibility was not granted at the moment of synthesize. Cmd+V did
    /// NOT land in the frontmost text element. Caller should show a CTA
    /// pointing at System Settings → Privacy & Security → Accessibility.
    case accessibilityDenied
}

/// Snapshot of restorable `NSPasteboard` payloads so steal-and-paste can put
/// the user's prior clipboard back after ⌘V has been delivered.
///
/// Captures `.string` and `.rtf` when present (plus a few other declared
/// restorable types). Skips promised / transient types that break
/// `writeObjects` round-trips.
struct PasteboardSnapshot: Equatable {
    /// Parallel to `NSPasteboard.pasteboardItems`: each element is one item's
    /// type → data map. Empty means the pasteboard held nothing we could copy.
    let items: [[NSPasteboard.PasteboardType: Data]]

    /// Types we can faithfully round-trip. `.string` + `.rtf` are the
    /// steal-and-paste contract; the rest are best-effort extras that still
    /// restore cleanly via `NSPasteboardItem.setData`.
    static let restorableTypes: [NSPasteboard.PasteboardType] = [
        .string,
        .rtf,
        .rtfd,
        .html,
        .png,
        .tiff,
        .pdf,
    ]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        guard let pbItems = pasteboard.pasteboardItems else {
            return PasteboardSnapshot(items: [])
        }
        let captured: [[NSPasteboard.PasteboardType: Data]] = pbItems.compactMap { item in
            var payload: [NSPasteboard.PasteboardType: Data] = [:]
            for type in restorableTypes where item.types.contains(type) {
                if let data = item.data(forType: type) {
                    payload[type] = data
                }
            }
            return payload.isEmpty ? nil : payload
        }
        return PasteboardSnapshot(items: captured)
    }

    /// Returns `true` when the pasteboard accepted the restored objects (or
    /// when the snapshot was empty and contents were cleared).
    @discardableResult
    func restore(onto pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        guard !items.isEmpty else { return true }
        let objects: [NSPasteboardItem] = items.map { payload in
            let item = NSPasteboardItem()
            for (type, data) in payload {
                item.setData(data, forType: type)
            }
            return item
        }
        return pasteboard.writeObjects(objects)
    }

    /// Convenience for tests / diagnostics — string payload of the first item.
    var stringValue: String? {
        guard let data = items.first?[.string] else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Convenience for tests / diagnostics — RTF payload of the first item.
    var rtfData: Data? {
        items.first?[.rtf]
    }
}

/// Sends text to the frontmost text field by writing to the pasteboard first then
/// synthesizing a Cmd+V. Throws `PasteError` on the two failure paths the prior
/// implementation swallowed silently. All state mutations go through
/// `@MainActor` isolation so the class is safe for cross-actor sharing; the
/// explicit `@unchecked Sendable` is what Swift 6 strict-concurrency needs to
/// validate the `static let shared` singleton and to allow the type to travel
/// through `NotificationCenter` payloads.
@MainActor
public final class PasteAutomation: ObservableObject, @unchecked Sendable {
    public static let shared = PasteAutomation()

    /// Published flag the onboarding PermissionsStep observes so the row can
    /// flip from "Grant Permission" to "Granted ✓" without a full SwiftUI body
    /// re-evaluation. Updated by `requestPermission()` after AX probes.
    @Published public private(set) var isPermissionGranted: Bool = AXIsProcessTrusted()

    /// Overridable Accessibility probe — production uses `AXIsProcessTrusted`.
    /// Unit tests inject a deterministic closure so the denied path can be
    /// exercised without live TCC / AX.
    var accessibilityTrustedCheck: () -> Bool = { AXIsProcessTrusted() }

    /// Delay after synthesizing ⌘V before restoring the prior pasteboard so
    /// the frontmost app has time to read our temporary string.
    ///
    /// This delay is the only thing standing between a clean paste and the
    /// target app reading the *restored* (prior) clipboard instead of the
    /// signoff. Some paste consumers — Electron/Slack/Chrome — read the
    /// pasteboard asynchronously via IPC well after the ⌘V key event is
    /// delivered; too short a window and the restore lands first, so the user
    /// sees their old clipboard pasted instead of the signoff (reported as
    /// "occasionally pastes whatever is in my clipboard"). 200 ms raced
    /// Mail/Slack/Electron in practice; 800 ms reliably covers the slow
    /// consumers we've seen, and is safe to lengthen because the `changeCount`
    /// guard below skips restore entirely if the user copies something else
    /// during the window. Tests zero this out.
    var pasteboardRestoreDelayNanoseconds: UInt64 = 800_000_000

    /// Success-path side effect hook. Left as a no-op here; callers may assign
    /// an async closure to react to a confirmed paste. Currently unused by the
    /// app — kept as an injection point for tests and future wiring. (Earlier
    /// copy here referenced a `CelebrationCapsuleCoordinator` that was never
    /// actually wired at launch; that description was stale and removed.)
    public var onPasteSucceeded: (String) async -> Void = { _ in }

    /// Re-polls Accessibility without showing the OS prompt. Used by the
    /// onboarding PermissionsStep when the app becomes active again after the
    /// user may have flipped the toggle in System Settings.
    @discardableResult
    public func refreshPermissionState() -> Bool {
        let granted = accessibilityTrustedCheck()
        isPermissionGranted = granted
        return granted
    }

    /// Prompts the user to grant Accessibility (idempotent — first call shows
    /// the OS prompt, subsequent calls silently re-poll). Returns the resulting
    /// trusted state so callers can update their UI without an extra probe.
    @discardableResult
    public func requestPermission() -> Bool {
        // Clear the `signoff.axPrompted` UserDefaults gate so the OS will show
        // the prompt even if the user denied earlier — this is the explicit
        // retry path from the onboarding PermissionsStep.
        UserDefaults.standard.removeObject(forKey: "signoff.axPrompted")
        let opts = ["AXTrustedCheckOptionPrompt": NSNumber(value: true)] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(opts)
        isPermissionGranted = granted
        return granted
    }

    /// Sends `text` to the frontmost text field by writing to the pasteboard
    /// then synthesizing ⌘V. Throws:
    ///   - `PasteError.pasteboardWriteFailed` if NSPasteboard refused the write
    ///   - `PasteError.accessibilityDenied` if the user hasn't granted
    ///     Accessibility (Cmd+V cannot synthesize without it)
    /// On the success path the prior pasteboard is restored after a short delay
    /// so the steal-and-paste does not permanently clobber the user's clipboard.
    /// Fires a `.generic` haptic on success path so the partner gets
    /// tactile feedback even when no UI is visible.
    public func paste(_ text: String) async throws {
        try await paste { pb in
            pb.clearContents()
            guard pb.setString(text, forType: .string) else {
                throw PasteError.pasteboardWriteFailed
            }
        }
    }

    /// Same steal-and-paste flow as `paste(_:)`, but writes a rich-text
    /// attributed string (RTF + RTFD + plain) instead of a bare string — used
    /// by the Custom bucket's user-authored footer so formatting and embedded
    /// images survive the ⌘V delivery into Mail / Notes / Pages.
    public func paste(_ attributed: NSAttributedString) async throws {
        try await paste { pb in
            guard RichTextFooter.writeRTF(attributed, to: pb) else {
                throw PasteError.pasteboardWriteFailed
            }
        }
    }

    /// Shared steal-and-paste pipeline. The `write` closure commits the
    /// temporary clipboard contents; everything after is the ⌘V synthesis and
    /// the delayed prior-clipboard restore.
    private func paste(write: (NSPasteboard) throws -> Void) async throws {
        // 1. Never fire the system AX prompt until the brand explainer has
        // been shown (SignoffUI posts `.signoffNeedsA11yExplainer`). Prevents
        // the cold "ugh, more permissions" system sheet on first ⌃⌘1.
        let explainerKey = "SignoffA11yExplainerShown"
        let promptedKey = "signoff.axPrompted"
        if !UserDefaults.standard.bool(forKey: explainerKey) {
            isPermissionGranted = accessibilityTrustedCheck()
            if !isPermissionGranted {
                NotificationCenter.default.post(name: .signoffNeedsA11yExplainer, object: nil)
                throw PasteError.accessibilityDenied
            }
        } else if !UserDefaults.standard.bool(forKey: promptedKey) {
            // The framework constant `kAXTrustedCheckOptionPrompt` is exposed
            // as a mutable global CFString, which Swift 6 strict-concurrency
            // rejects because it represents shared mutable state. The literal
            // string "AXTrustedCheckOptionPrompt" is the exact same CFString
            // value and is provably Sendable, so we use it directly.
            let opts = ["AXTrustedCheckOptionPrompt": NSNumber(value: true)] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
            UserDefaults.standard.set(true, forKey: promptedKey)
        }

        // 2. Hard-fail if Accessibility is still denied. Cmd+V synthesis is a
        // silent no-op without trust — throwing lets `AppState.generateNow()`
        // surface the Accessibility CTA / ErrorFixCard path.
        let trusted = accessibilityTrustedCheck()
        isPermissionGranted = trusted
        guard trusted else {
            throw PasteError.accessibilityDenied
        }

        let pb = NSPasteboard.general
        let prior = PasteboardSnapshot.capture(from: pb)

        let changeCountBefore = pb.changeCount
        do {
            try write(pb)
        } catch {
            prior.restore(onto: pb)
            throw error
        }

        // Guardrail: if the pasteboard changeCount didn't advance, another
        // app or clipboard manager may have locked it. Alerts the user rather
        // than silently pasting stale content. See Batch 2.2.
        guard pb.changeCount != changeCountBefore else {
            prior.restore(onto: pb)
            throw PasteError.pasteboardWriteFailed
        }

        // We now own the clipboard with the temporary sign-off. `defer` guarantees
        // we never leave it stuck if anything after this point exits early —
        // delayed restore clears the flag when it succeeds (or when the user
        // already replaced the clipboard themselves).
        let ourChangeCount = pb.changeCount
        var restorePending = true
        defer {
            if restorePending {
                prior.restore(onto: pb)
            }
        }

        // Tactile acknowledgment — fires immediately on pasteboard commit so
        // Cmd+V users without vocal system feedback still get a "click."
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)

        // 3. Synthesize Cmd+V down/up — only reached when Accessibility is trusted.
        let src = CGEventSource(stateID: .hidSystemState)
        let keyV: CGKeyCode = 9
        if let down = CGEvent(keyboardEventSource: src, virtualKey: keyV, keyDown: true) {
            down.flags = .maskCommand
            down.post(tap: .cgAnnotatedSessionEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: keyV, keyDown: false) {
            up.flags = .maskCommand
            up.post(tap: .cgAnnotatedSessionEventTap)
        }
        await Task.yield()

        // 4. Give the frontmost app time to consume our temporary pasteboard
        // contents before we put the user's prior clipboard back. `try?` so a
        // cancelled sleep still falls through to restore (sign-off must not
        // linger). Skip restore if changeCount moved — the user/another app
        // already replaced our temporary contents.
        if pasteboardRestoreDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: pasteboardRestoreDelayNanoseconds)
        }
        if pb.changeCount == ourChangeCount {
            // Only clear the defer flag when restore actually lands; a failed
            // writeObjects leaves restorePending so defer retries and the
            // temporary sign-off cannot stick forever.
            if prior.restore(onto: pb) {
                restorePending = false
            }
        } else {
            // User / clipboard manager already replaced our temporary contents.
            restorePending = false
        }
    }
}
