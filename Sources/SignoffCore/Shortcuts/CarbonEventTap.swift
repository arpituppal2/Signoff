import Foundation
import CoreGraphics
import AppKit
import os.log

public final class CarbonEventTap: @unchecked Sendable {
    /// Tri-state diagnostic for `CarbonEventTap.start()` so callers can route
    /// the failure to UI surfaces (HUD/banner) instead of silently
    /// dead-keystroking. Nested inside the class so the canonical lookup
    /// path is `CarbonEventTap.TapFailure`. Explicitly Sendable so it can
    /// travel across the `@unchecked Sendable` boundary into
    /// `NotificationCenter.default.post(name:object:)` payloads.
    public enum TapFailure: Error, Sendable, Equatable {
        /// `CGEvent.tapCreate` returned nil — usually means Input Monitoring
        /// permission wasn't granted, or the system already bound the chord
        /// (e.g. Mission Control ⌃⌘1). Accessibility is a separate permission
        /// used for paste synthesis, not for installing the listen tap.
        case eventTapDenied(reason: String)
        /// The tap was created but `CFMachPortCreateRunLoopSource` failed.
        case runLoopSourceCreateFailed
        /// Tap wired and source installed but `CGEvent.tapIsEnabled` returned
        /// false post-`tapEnable(true:)` — the system is holding the chord.
        case tapEnableFailed
    }

    private static let log = Logger(subsystem: "com.signoff", category: "CarbonEventTap")
    public struct Flag: OptionSet, Sendable, Equatable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let shift   = Flag(rawValue: 1 << 0)
        public static let control = Flag(rawValue: 1 << 1)
        public static let option  = Flag(rawValue: 1 << 2)
        public static let command = Flag(rawValue: 1 << 3)
        public static let cmdCtrl: Flag = [.command, .control]
        public static let optCmd:  Flag = [.command, .option]
        public func contains(_ other: CarbonEventTap.Flag) -> Bool {
            (rawValue & other.rawValue) == other.rawValue
        }
    }

    public typealias EventHandler = @Sendable (CGEvent?) -> CGEvent?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let handler: EventHandler

    public init(_ handler: @escaping EventHandler) {
        self.handler = handler
    }

    /// Install the system event tap. Returns the diagnostic so callers can
    /// surface a visible UI error rather than silently eating keystrokes.
    /// Idempotent — re-calling when already running is a no-op success.
    ///
    /// DX note: we do **not** try to reverse-engineer per-chord Mission Control
    /// ownership inside `canTap` (CGEvent taps are not chord-addressable).
    /// Reliability DX lives upstream — Settings → Shortcuts recorder, Pause
    /// Shortcuts, ⌥⌘ fallback, and `TapFailure` → UI banner.

    public func start() -> Result<Void, TapFailure> {
        guard tap == nil else { return .success(()) }
        // Note: we deliberately do NOT gate on `CGPreflightListenEventAccess()`
        // here. On some Macs the preflight returns false even after Input
        // Monitoring is granted, which would both re-prompt via
        // `CGRequestListenEventAccess()` and mis-report a working setup. The
        // tap itself is the source of truth: if `CGEvent.tapCreate` returns nil,
        // THAT is a genuine denial and we request + report. If it succeeds, the
        // permission is fine and nothing extra is asked.
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        // macOS 26 SDK: `CGEventTapCreate` has been replaced by a Swift-only
        // class method `CGEvent.tapCreate(tap:place:options:eventsOfInterest:callback:userInfo:)`.
        let userInfo: UnsafeMutableRawPointer = Unmanaged.passUnretained(self).toOpaque()
        let tapCB: CGEventTapCallBack = { _, _, event, infoPtr in
            guard let infoPtr = infoPtr else { return Unmanaged.passRetained(event) }
            let owner = Unmanaged<CarbonEventTap>.fromOpaque(infoPtr).takeUnretainedValue()
            let handled = owner.handle(event: event)
            return handled.map { Unmanaged.passRetained($0) }
        }
        guard let tapRef = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: tapCB,
            userInfo: userInfo
        ) else {
            // Genuine denial: CGEvent.tapCreate returned nil. Surface the
            // system prompt so the user can grant Input Monitoring, then
            // report the failure (SignoffDelegate presents the alert).
            _ = InputMonitoringAccess.request()
            let reason = "CGEvent.tapCreate returned nil (Input Monitoring likely not granted, or system already bound the chord)."
            Self.log.error("\(reason, privacy: .public)")
            return .failure(.eventTapDenied(reason: reason))
        }
        self.tap = tapRef
        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tapRef, 0) else {
            Self.log.error("CFMachPortCreateRunLoopSource returned nil after successful tap create.")
            self.tap = nil
            return .failure(.runLoopSourceCreateFailed)
        }
        self.source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tapRef, enable: true)
        if !CGEvent.tapIsEnabled(tap: tapRef) {
            Self.log.error("Tap created and source installed, but CGEvent.tapIsEnabled returns false — system has captured the chord.")
            self.stop()
            return .failure(.tapEnableFailed)
        }
        return .success(())
    }

    public func stop() {
        guard let tapRef = tap else { return }
        CGEvent.tapEnable(tap: tapRef, enable: false)
        if let source = source {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        tap = nil
        source = nil
    }

    private func handle(event: CGEvent?) -> CGEvent? {
        return handler(event)
    }

    public static func modifiersOf(_ event: CGEvent) -> Flag {
        var f = Flag()
        let cgFlags = event.flags
        if cgFlags.contains(.maskShift)    { f.insert(.shift) }
        if cgFlags.contains(.maskControl)  { f.insert(.control) }
        if cgFlags.contains(.maskAlternate){ f.insert(.option) }
        if cgFlags.contains(.maskCommand)  { f.insert(.command) }
        return f
    }

    public static func keyCodeOf(_ event: CGEvent) -> Int32 {
        Int32(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    }

    /// Installability smoke test — not a per-chord ownership check.
    /// `keyCode` / `modifiers` are accepted for API clarity at call sites but
    /// unused: CGEvent taps listen to an event mask, not a specific chord.
    /// Callers must treat `false` as "Input Monitoring / system gate blocked
    /// taps" and rely on `start()` → `TapFailure` + Settings rebind for
    /// Mission Control collisions.
    public static func canTap(keyCode: Int32, modifiers: UInt32) -> Bool {
        _ = keyCode
        _ = modifiers
        // Do not preflight via CGPreflightListenEventAccess() — it can report
        // false on Macs where Input Monitoring is actually granted. A listen-only
        // tapCreate succeeding is the authoritative installability signal.
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let passthroughCB: CGEventTapCallBack = { _, _, event, _ in
            Unmanaged.passRetained(event)
        }
        guard let tapRef = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: passthroughCB,
            userInfo: nil
        ) else {
            return false
        }
        let enabled = CGEvent.tapIsEnabled(tap: tapRef)
        CGEvent.tapEnable(tap: tapRef, enable: false)
        CFMachPortInvalidate(tapRef)
        return enabled
    }
}
