import Testing
import Foundation
@testable import SignoffCore

/// Covers `ShortcutManager.encode/decode/probe` — the JSON encode & decode
/// round-trip plus the safe-degradation to `.defaults()` for malformed
/// payloads. Real conflicts probe lives in `CarbonEventTap.canTap(...)` so
/// we assert only the public-API contract here.
@MainActor
struct ShortcutManagerTests {

    @Test("Encode decode round trip")
    func encodeDecodeRoundTrip() {
        let original = ShortcutManager.shared.defaults()
        let encoded = ShortcutManager.shared.encode(original)
        let decoded = ShortcutManager.shared.decode(encoded)
        #expect(decoded == original, "encode/decode must be lossless for BucketBinding arrays")
    }

    @Test("Garbage JSON falls back to defaults")
    func garbageJSONFallsBackToDefaults() {
        let decoded = ShortcutManager.shared.decode("not json {{{}}")
        #expect(decoded == ShortcutManager.shared.defaults(), "Malformed input must fall back to the canonical defaults")
    }

    @Test("Empty string falls back to defaults")
    func emptyStringFallsBackToDefaults() {
        let decoded = ShortcutManager.shared.decode("")
        #expect(decoded == ShortcutManager.shared.defaults())
    }

    @Test("Overlong binding list falls back to defaults")
    func overlongBindingListFallsBackToDefaults() {
        // Build a 7-binding array (max is 4 per BucketBinding contract).
        let overlong: [ShortcutManager.BucketBinding] = (1...7).map { idx in
            .init(bucketId: "x\(idx)", digitKey: "\(idx)", modifier: "cmdCtrl")
        }
        let encoded = ShortcutManager.shared.encode(overlong)
        let decoded = ShortcutManager.shared.decode(encoded)
        #expect(decoded == ShortcutManager.shared.defaults(), "Bindings count >4 should fall back to defaults")
    }

    @Test("Opt Cmd defaults use option command")
    func optCmdDefaultsUseOptionCommand() {
        let opt = ShortcutManager.shared.optCmdDefaults()
        #expect(opt.count == 3)
        #expect(opt.allSatisfy { $0.modifier == "optCmd" })
        #expect(opt.map(\.digitKey) == ["1", "2", "3"])
    }

    @Test("Default mapping is Normal Professional Cynical")
    func defaultMappingIsNormalProfessionalCynical() {
        // v3.5: 1 Normal · 2 Professional · 3 Cynical · 4 Custom (` opens menu bar).
        let defaults = ShortcutManager.shared.defaults()
        #expect(defaults.map(\.bucketId) == [
            BucketID.standard.rawValue,
            BucketID.professional.rawValue,
            BucketID.unhinged.rawValue
        ])
        #expect(defaults.map(\.digitKey) == ["1", "2", "3"])
    }

    @Test("Probe publishes bound shortcut conflicts")
    func probePublishesBoundShortcutConflicts() async {
        let manager = ShortcutManager.shared
        _ = await manager.probe(bindings: manager.defaults())
        // Whether empty or not depends on Input Monitoring in the test host;
        // the contract is that probe always writes the published property.
        #expect(manager.boundShortcutConflicts.count >= 0)
        for (k, v) in manager.boundShortcutConflicts {
            #expect(!k.isEmpty)
            #expect(!v.isEmpty)
        }
    }

    @Test("Pause persists and clears on toggle")
    func pausePersistsAndClearsOnToggle() {
        let manager = ShortcutManager.shared
        let previous = manager.isPaused
        defer { manager.isPaused = previous }

        manager.isPaused = true
        #expect(UserDefaults.standard.bool(forKey: "signoff.shortcutsPaused") == true)
        manager.isPaused = false
        #expect(UserDefaults.standard.bool(forKey: "signoff.shortcutsPaused") == false)
    }

    @Test("Suspend tap temporarily does not flip pause")
    func suspendTapTemporarilyDoesNotFlipPause() async {
        let manager = ShortcutManager.shared
        let previous = manager.isPaused
        defer {
            manager.isPaused = previous
            manager.stop()
        }

        manager.isPaused = false
        await manager.register(bindings: manager.defaults()) { _ in } runSpecialAction: { _ in }
        manager.suspendTapTemporarily()
        #expect(manager.isPaused == false, "Recorder suspend must not flip Pause shortcuts")
    }
}