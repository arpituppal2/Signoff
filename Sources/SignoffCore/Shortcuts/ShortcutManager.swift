import Foundation
import Carbon.HIToolbox

@MainActor
public final class ShortcutManager: ObservableObject {
    public static let shared = ShortcutManager()

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

    private static let pausedDefaultsKey = "signoff.shortcutsPaused"

    private var tap: CarbonEventTap?

    public init() {
        self.isPaused = UserDefaults.standard.bool(forKey: Self.pausedDefaultsKey)
    }

    public static let openPopoverShortcut = Notification.Name("signoff.openPopoverShortcut")

    public func defaults() -> [BucketBinding] {
        [
            .init(bucketId: BucketID.professional.rawValue, digitKey: "1", modifier: "cmdCtrl"),
            .init(bucketId: BucketID.standard.rawValue,     digitKey: "2", modifier: "cmdCtrl"),
            .init(bucketId: BucketID.unhinged.rawValue,     digitKey: "3", modifier: "cmdCtrl"),
            .init(bucketId: BucketID.custom.rawValue,       digitKey: "4", modifier: "cmdCtrl"),
            .init(bucketId: BucketID.list.rawValue,         digitKey: "5", modifier: "cmdCtrl"),
            .init(bucketId: BucketID.footer.rawValue,       digitKey: "6", modifier: "cmdCtrl"),
        ]
    }

    /// Recommended fallback when Mission Control / Spaces owns ⌃⌘1–6.
    public func optCmdDefaults() -> [BucketBinding] {
        defaults().map {
            BucketBinding(bucketId: $0.bucketId, digitKey: $0.digitKey, modifier: "optCmd")
        }
    }

    public func encode(_ bindings: [BucketBinding]) -> String {
        let data = (try? JSONEncoder().encode(bindings)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    public func decode(_ json: String) -> [BucketBinding] {
        guard let data = json.data(using: .utf8),
              let bindings = try? JSONDecoder().decode([BucketBinding].self, from: data),
              bindings.count <= 6 else {
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
            let flags = binding.modifier == "optCmd"
                ? CarbonEventTap.Flag.optCmd.rawValue
                : CarbonEventTap.Flag.cmdCtrl.rawValue
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

    public func register(bindings: [BucketBinding], runAction: @escaping @Sendable (String) -> Void) async {
        tap?.stop()
        guard !isPaused else {
            tap = nil
            return
        }

        let keyCodeForDigit = ShortcutManager.keyCodeForDigit
        let flagForModifier: @Sendable (String) -> CarbonEventTap.Flag = { raw in
            raw == "optCmd" ? .optCmd : .cmdCtrl
        }
        let t = CarbonEventTap { event in
            guard let event = event else { return nil }
            let keyCode = CarbonEventTap.keyCodeOf(event)
            let mods = CarbonEventTap.modifiersOf(event)
            let containsCtrlCmd = mods.contains(.cmdCtrl)
            
            // Spec §7: ⌃⌘` (backtick) opens the popover
            if keyCode == kVK_ANSI_Grave, containsCtrlCmd {
                Task { @MainActor in NotificationCenter.default.post(name: Self.openPopoverShortcut, object: nil) }
                return nil
            }
            
            // ⌃⌘, opens Settings
            if keyCode == kVK_ANSI_Comma, containsCtrlCmd {
                Task { @MainActor in NotificationCenter.default.post(name: .openSettingsShortcutTriggered, object: nil) }
                return nil
            }
            
            // ⌃⇧C copies last signoff
            if keyCode == kVK_ANSI_C, mods.contains(.cmdCtrl), mods.contains(.shift) {
                Task { @MainActor in NotificationCenter.default.post(name: Notification.Name("com.signoff.copyLast"), object: nil) }
                return nil
            }
            
            // ⌃⌘1–6 generates in specific buckets
            for binding in bindings {
                let expected = flagForModifier(binding.modifier)
                if keyCode == keyCodeForDigit(binding.digitKey),
                   mods.contains(expected) {
                    let bucketId = binding.bucketId
                    Task { @MainActor in runAction(bucketId) }
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
            recordTapFailureConflicts(for: bindings, failure: failure)
            NotificationCenter.default.post(name: .shortcutTapFailed, object: failure)
        case .success:
            // Tap installed; probe-time conflicts were installability noise.
            clearConflicts()
        }
    }

    public func stop() {
        tap?.stop()
        tap = nil
    }

    /// Tear down the Carbon tap without flipping `isPaused`.
    /// Used by Settings → Shortcuts while `ShortcutRecorderView` is capturing
    /// a chord — a live `.defaultTap` at head-insert would swallow ⌃⌘/⌥⌘
    /// before the local `NSEvent` monitor can see them.
    public func suspendTapTemporarily() {
        stop()
    }

    public func displayLabel(for binding: BucketBinding) -> String {
        let mod = binding.modifier == "optCmd" ? "⌥⌘" : "⌃⌘"
        return "\(mod)\(binding.digitKey)"
    }

    private nonisolated static func keyCodeForDigit(_ d: String) -> Int32 {
        switch d {
        case "1": return Int32(kVK_ANSI_1)
        case "2": return Int32(kVK_ANSI_2)
        case "3": return Int32(kVK_ANSI_3)
        case "4": return Int32(kVK_ANSI_4)
        case "5": return Int32(kVK_ANSI_5)
        case "6": return Int32(kVK_ANSI_6)
        default:  return -1
        }
    }

    private nonisolated static func keyCodeForDigitKey(_ d: String) -> Int32 {
        keyCodeForDigit(d)
    }

    private nonisolated static func nameForBinding(_ b: BucketBinding) -> String {
        let mod = b.modifier == "optCmd" ? "⌥⌘" : "⌃⌘"
        return "Mission Control / Spaces may own \(mod)\(b.digitKey)"
    }
}

// Carbon key codes that aren't in the public Carbon header enum.
public let kVK_ANSI_Grave: Int32 = 50
public let kVK_ANSI_C: Int32 = 8
public let kVK_ANSI_Comma: Int32 = 43
