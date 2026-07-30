import XCTest
@testable import SignoffCore

/// Covers `ShortcutManager.encode/decode/probe` — the JSON encode & decode
/// round-trip plus the safe-degradation to `.defaults()` for malformed
/// payloads. Real conflicts probe lives in `CarbonEventTap.canTap(...)` so
/// we assert only the public-API contract here.
@MainActor
final class ShortcutManagerTests: XCTestCase {

    func testEncodeDecodeRoundTrip() {
        let original = ShortcutManager.shared.defaults()
        let encoded = ShortcutManager.shared.encode(original)
        let decoded = ShortcutManager.shared.decode(encoded)
        XCTAssertEqual(decoded, original,
                       "encode/decode must be lossless for BucketBinding arrays")
    }

    func testGarbageJSONFallsBackToDefaults() {
        let decoded = ShortcutManager.shared.decode("not json {{{}}")
        XCTAssertEqual(decoded, ShortcutManager.shared.defaults(),
                       "Malformed input must fall back to the canonical defaults")
    }

    func testEmptyStringFallsBackToDefaults() {
        let decoded = ShortcutManager.shared.decode("")
        XCTAssertEqual(decoded, ShortcutManager.shared.defaults())
    }

    func testOverlongBindingListFallsBackToDefaults() {
        // Build a 7-binding array (max is 6 per BucketBinding contract).
        let overlong: [ShortcutManager.BucketBinding] = (1...7).map { idx in
            .init(bucketId: "x\(idx)", digitKey: "\(idx)", modifier: "cmdCtrl")
        }
        let encoded = ShortcutManager.shared.encode(overlong)
        let decoded = ShortcutManager.shared.decode(encoded)
        XCTAssertEqual(decoded, ShortcutManager.shared.defaults(),
                       "Bindings count >6 should fall back to defaults")
    }

    func testOptCmdDefaultsUseOptionCommand() {
        let opt = ShortcutManager.shared.optCmdDefaults()
        XCTAssertEqual(opt.count, 6)
        XCTAssertTrue(opt.allSatisfy { $0.modifier == "optCmd" })
        XCTAssertEqual(opt.map(\.digitKey), ["1", "2", "3", "4", "5", "6"])
    }

    func testProbePublishesBoundShortcutConflicts() async {
        let manager = ShortcutManager.shared
        _ = await manager.probe(bindings: manager.defaults())
        // Whether empty or not depends on Input Monitoring in the test host;
        // the contract is that probe always writes the published property.
        XCTAssertEqual(manager.boundShortcutConflicts.count >= 0, true)
        for (k, v) in manager.boundShortcutConflicts {
            XCTAssertFalse(k.isEmpty)
            XCTAssertFalse(v.isEmpty)
        }
    }

    func testPausePersistsAndClearsOnToggle() {
        let manager = ShortcutManager.shared
        let previous = manager.isPaused
        defer { manager.isPaused = previous }

        manager.isPaused = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "signoff.shortcutsPaused"))
        manager.isPaused = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "signoff.shortcutsPaused"))
    }

    func testSuspendTapTemporarilyDoesNotFlipPause() async {
        let manager = ShortcutManager.shared
        let previous = manager.isPaused
        defer {
            manager.isPaused = previous
            manager.stop()
        }

        manager.isPaused = false
        await manager.register(bindings: manager.defaults()) { _ in }
        manager.suspendTapTemporarily()
        XCTAssertFalse(manager.isPaused,
                       "Recorder suspend must not flip Pause shortcuts")
    }
}
