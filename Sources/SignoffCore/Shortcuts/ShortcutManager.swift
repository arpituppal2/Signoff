import Foundation
import Carbon.HIToolbox
import os.log

@MainActor
public final class ShortcutManager: ObservableObject {
    public static let shared = ShortcutManager()

    private static let log = Logger(subsystem: "com.signoff", category: "ShortcutManager")

    public struct BucketBinding: Codable, Sendable, Equatable {
        public let bucketId: String
        public var digitKey: String              // "1"…"6"
        public var modifier: String              // "cmdCtrl", "optCmd"

        public init(bucketId: String, digitKey: String, modifier: String) {
            self.bucketId = bucketId
            self.digitKey = digitKey
            self.modifier = modifier
        }
    }

    public struct SpecialActionBinding: Codable, Sendable, Equatable {
        public let action: SpecialAction
        public var digitKey: String
        public var modifier: String

        public init(action: SpecialAction, digitKey: String, modifier: String) {
            self.action = action
            self.digitKey = digitKey
            self.modifier = modifier
        }
    }

    /// Per-digit collision labels from the last `probe` / tap-failure path.
    /// Settings → Shortcuts reads this for the conflict banner.
    @Published public private(set) var boundShortcutConflicts: [String: String] = [:]

    /// When true, the Carbon tap is torn down and chord actions are ignored.
    /// Persisted in UserDefaults so a paused session survives relaunch.
    @Published public var isPaused: Bool {
        didSet {
            UserDefaults.standard.set(isPaused, forKey: Self.pausedDefaultsKey)
        }
    }

    /// True when a Carbon event tap is installed and verified enabled. This is
    /// the authoritative "Input Monitoring works" signal — unlike
    /// `CGPreflightListenEventAccess()`, it reflects the REAL tap install
    /// result, so it does not flicker on Macs where permission is already
    /// granted. Publishes so the popover indicator can react to failures.
    @Published public private(set) var isTapFunctional: Bool = false

    public static let pausedDefaultsKey = "signoff.shortcutsPaused"

    /// Special action identifiers for non-bucket shortcuts.
    public enum SpecialAction: String, CaseIterable, Codable, Sendable {
        case pasteAfterSignoff = "pasteAfterSignoff"
    }

    private var tap: CarbonEventTap?

    public init() {
        self.isPaused = UserDefaults.standard.bool(forKey: Self.pausedDefaultsKey)
    }

    public func defaults() -> [BucketBinding] {
        [
            .init(bucketId: BucketID.standard.rawValue,     digitKey: "1", modifier: "ctrlOpt"),
            .init(bucketId: BucketID.professional.rawValue, digitKey: "2", modifier: "ctrlOpt"),
            .init(bucketId: BucketID.unhinged.rawValue,     digitKey: "3", modifier: "ctrlOpt"),
        ]
    }

    /// Recommended fallback when Mission Control / Spaces owns ⌃⌘1–4.
    public func optCmdDefaults() -> [BucketBinding] {
        defaults().map {
            BucketBinding(bucketId: $0.bucketId, digitKey: $0.digitKey, modifier: "optCmd")
        }
    }

    /// Default fallback — ⌃⌥1–4 (Control-Option digits).
    public func ctrlOptDefaults() -> [BucketBinding] {
        defaults().map {
            BucketBinding(bucketId: $0.bucketId, digitKey: $0.digitKey, modifier: "ctrlOpt")
        }
    }

    public func encode(_ bindings: [BucketBinding]) -> String {
        let data = (try? JSONEncoder().encode(bindings)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    public func decode(_ json: String) -> [BucketBinding] {
        guard let data = json.data(using: .utf8),
              let bindings = try? JSONDecoder().decode([BucketBinding].self, from: data),
              bindings.count <= 3 else {
            return defaults()
        }
        return bindings.isEmpty ? defaults() : bindings
    }

    /// Best-effort installability probe. `CarbonEventTap.canTap` checks whether
    /// *any* listen-only tap can be created (Input Monitoring / system gate),
    /// not whether Mission Control owns a specific chord — per-chord ownership
    /// only shows up after `start()` via `tapEnableFailed`. We still publish
    /// results on `boundShortcutConflicts` so Settings can show a banner.
    public func probe(bindings: [BucketBinding]) async -> [String: String] {
        var conflicts: [String: String] = [:]
        let monitoringOK = InputMonitoringAccess.isGranted()
        for binding in bindings {
            let keyCode = ShortcutManager.keyCodeForDigit(binding.digitKey)
            let flags: UInt32
            switch binding.modifier {
            case "ctrlOpt":
                flags = CarbonEventTap.Flag.ctrlOpt.rawValue
            case "optCmd":
                flags = CarbonEventTap.Flag.optCmd.rawValue
            default:
                flags = CarbonEventTap.Flag.cmdCtrl.rawValue
            }
            if !CarbonEventTap.canTap(keyCode: keyCode, modifiers: flags) {
                if !monitoringOK {
                    conflicts[binding.digitKey] = "Input Monitoring required for \(displayLabel(for: binding))"
                } else {
                    conflicts[binding.digitKey] = ShortcutManager.nameForBinding(binding)
                }
            }
        }
        boundShortcutConflicts = conflicts
        return conflicts
    }

    /// Populate conflicts from a tap-install failure (DX path when the probe
    /// could not see a per-chord Mission Control collision).
    public func recordTapFailureConflicts(for bindings: [BucketBinding],
                                          failure: CarbonEventTap.TapFailure) {
        switch failure {
        case .eventTapDenied:
            boundShortcutConflicts = Dictionary(
                uniqueKeysWithValues: bindings.map {
                    ($0.digitKey, "Input Monitoring blocked — \(displayLabel(for: $0))")
                }
            )
        case .tapEnableFailed:
            boundShortcutConflicts = Dictionary(
                uniqueKeysWithValues: bindings.map {
                    ($0.digitKey, ShortcutManager.nameForBinding($0))
                }
            )
        case .runLoopSourceCreateFailed:
            boundShortcutConflicts = [
                "*": "Shortcut hub failed to wire (run-loop source)."
            ]
        }
    }

    public func clearConflicts() {
        boundShortcutConflicts = [:]
    }

    public func register(bindings: [BucketBinding],
                         specialBindings: [SpecialActionBinding] = [],
                         runAction: @escaping @Sendable (String) -> Void,
                         runSpecialAction: @escaping @Sendable (SpecialAction) -> Void) async {
        tap?.stop()
        guard !isPaused else {
            tap = nil
            isTapFunctional = false
            return
        }

        let keyCodesForDigit = ShortcutManager.keyCodesForDigit
        let flagForModifier: @Sendable (String) -> CarbonEventTap.Flag = { raw in
            raw == "ctrlOpt" ? .ctrlOpt : .optCmd
        }
        let t = CarbonEventTap { event in
            guard let event = event else { return nil }
            let keyCode = CarbonEventTap.keyCodeOf(event)
            let mods = CarbonEventTap.modifiersOf(event)
            let containsCtrlOpt = mods.contains(.ctrlOpt)

            // ⌘/ opens Settings (works globally, including when popover is open)
            // Support both kVK_ANSI_Slash (44) and 75 (what osascript sends for '/')
            if (keyCode == kVK_ANSI_Slash || keyCode == 75),
               mods.contains(.command), !mods.contains(.control), !mods.contains(.option) {
                Task { @MainActor in NotificationCenter.default.post(name: .openSettingsShortcutTriggered, object: nil) }
                return nil
            }

            // ⌃⌥, opens Settings
            if keyCode == kVK_ANSI_Comma, containsCtrlOpt {
                Task { @MainActor in NotificationCenter.default.post(name: .openSettingsShortcutTriggered, object: nil) }
                return nil
            }

            // ⌃⌥` opens the menu bar popover
            if keyCode == kVK_ANSI_Grave, containsCtrlOpt {
                Task { @MainActor in NotificationCenter.default.post(name: .toggleMenuBarPopover, object: nil) }
                return nil
            }

            // ⌃⇧C copies last signoff (Control+Shift only — no Command)
            if keyCode == kVK_ANSI_C,
               mods.contains(.control), mods.contains(.shift),
               !mods.contains(.command), !mods.contains(.option) {
                Task { @MainActor in NotificationCenter.default.post(name: Notification.Name("com.signoff.copyLast"), object: nil) }
                return nil
            }

            // ⌃⌥1–4 generates in specific buckets
            for binding in bindings {
                let expected = flagForModifier(binding.modifier)
                let keyCodes = keyCodesForDigit(binding.digitKey)
                if keyCodes.contains(keyCode), mods.contains(expected) {
                    let bucketId = binding.bucketId
                    Task { @MainActor in runAction(bucketId) }
                    return nil
                }
            }

            // Special actions (e.g., paste after signoff only)
            for binding in specialBindings {
                let expected = flagForModifier(binding.modifier)
                let keyCodes = keyCodesForDigit(binding.digitKey)
                if keyCodes.contains(keyCode), mods.contains(expected) {
                    let action = binding.action
                    Task { @MainActor in runSpecialAction(action) }
                    return nil
                }
            }

            return event
        }
        let result = t.start()
        tap = t
        switch result {
        case .failure(let failure):
            // Don't fight canTap false-negatives — surface the real install failure.
            isTapFunctional = false
            recordTapFailureConflicts(for: bindings, failure: failure)
            NotificationCenter.default.post(name: .shortcutTapFailed, object: failure)
        case .success:
            // Tap installed; probe-time conflicts were installability noise.
            isTapFunctional = true
            clearConflicts()
        }
    }

    public func stop() {
        tap?.stop()
        tap = nil
        isTapFunctional = false
    }

    /// Tear down the Carbon tap without flipping `isPaused`.
    /// Used by Settings → Shortcuts while `ShortcutRecorderView` is capturing
    /// a chord — a live `.defaultTap` at head-insert would swallow ⌃⌘/⌥⌘/⌃⌥
    /// before the local `NSEvent` monitor can see them.
    public func suspendTapTemporarily() {
        stop()
    }

    public func displayLabel(for binding: BucketBinding) -> String {
        let mod: String
        switch binding.modifier {
        case "ctrlOpt": mod = "⌃⌥"
        case "optCmd": mod = "⌥⌘"
        default: mod = "⌃⌘"
        }
        return "\(mod)\(binding.digitKey)"
    }

    // Both top-row (ANSI) and keypad key codes — osascript/keystroke may
    // send either depending on keyboard layout. Support both so shortcuts
    // work regardless of which physical key produces the digit.
    private nonisolated static func keyCodesForDigit(_ d: String) -> [Int32] {
        switch d {
        case "1": return [Int32(kVK_ANSI_1), 83]      // 18 (top row), 83 (keypad 1)
        case "2": return [Int32(kVK_ANSI_2), 84]      // 19, 84
        case "3": return [Int32(kVK_ANSI_3), 85]      // 20, 85
        case "4": return [Int32(kVK_ANSI_4), 86]      // 21, 86
        case "5": return [Int32(kVK_ANSI_5), 87]      // 23, 87
        case "6": return [Int32(kVK_ANSI_6), 88]      // 22, 88
        default:  return []
        }
    }

    private nonisolated static func keyCodeForDigit(_ d: String) -> Int32 {
        keyCodesForDigit(d).first ?? -1
    }

    private nonisolated static func nameForBinding(_ b: BucketBinding) -> String {
        let mod: String
        switch b.modifier {
        case "ctrlOpt": mod = "⌃⌥"
        case "optCmd": mod = "⌥⌘"
        default: mod = "⌃⌘"
        }
        return "Mission Control / Spaces may own \(mod)\(b.digitKey)"
    }
}

// Carbon key codes that aren't in the public Carbon header enum.
public let kVK_ANSI_C: Int32 = 8
public let kVK_ANSI_Comma: Int32 = 43
public let kVK_ANSI_Slash: Int32 = 44
public let kVK_ANSI_Grave: Int32 = 50
