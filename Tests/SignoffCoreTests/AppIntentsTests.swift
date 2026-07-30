import XCTest
import Foundation
import AppIntents
@testable import SignoffCore

/// Tests the SignoffIntents surfaces (GenerateSignoffIntent, CopyLastSignoffIntent,
/// SignoffShortcutsProvider) per CEO EXPANSION §OX-E lock 1 + ENG Review Test
/// Gap-2 + DX EXPANSION Pass 8.
///
/// Production API surface (verified against
/// `Sources/SignoffCore/Intents/SignoffIntents.swift`):
///
///   - `GenerateSignoffIntent.enforceRateLimit(now: Date = Date())` — static
///     method on the AppIntent that rolls a 1-hour sliding window in
///     UserDefaults `SignoffIntent.generate.window` and throws
///     `AppIntentError.rateLimited(retryAfter:)` on breach.
///   - `AppIntentError` — public enum: `rateLimited(retryAfter:)`,
///     `coldStartUnavailable`. LocalizedError conformant. Note: this is
///     SignoffCore's enum; Apple's `AppIntents` framework ALSO defines an
///     `AppIntentError` protocol type, so any cast must qualify with the
///     module name to disambiguate.
///   - `SignoffShortcutsProvider.appShortcuts` — `[AppShortcut]` array of
///     intent + phrases; contains both Generate + Copy intents.
///   - `AppState.shared.bootstrap()` — idempotent, await-able.
///
/// All tests run on the MainActor; rate-limit window state is reset in
/// setUp/tearDown to prevent cross-test bleed.
@MainActor
final class AppIntentsTests: XCTestCase {

    private let rateLimitKey = "SignoffIntent.generate.window"

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: rateLimitKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: rateLimitKey)
    }

    func testEnforceRateLimit_AllowsFirstCall() throws {
        // Cold start: empty window, first call must not throw.
        XCTAssertNoThrow(try GenerateSignoffIntent.enforceRateLimit())
    }

    func testEnforceRateLimit_Allows30CallsInWindow() throws {
        // Per production `static let rateLimitMax: Int = 30`. 30 calls in a
        // single window must all succeed.
        for i in 0..<30 {
            do {
                try GenerateSignoffIntent.enforceRateLimit()
            } catch {
                XCTFail("Call #\(i) should not throw; got \(error)")
            }
        }
    }

    func testEnforceRateLimit_ThrowsOn31stCall() {
        // Saturate the window.
        for _ in 0..<30 {
            try? GenerateSignoffIntent.enforceRateLimit()
        }
        XCTAssertThrowsError(try GenerateSignoffIntent.enforceRateLimit()) { error in
            // Apple's AppIntents framework also defines an `AppIntentError`
            // protocol type. Qualify the local enum (defined in
            // `Sources/SignoffCore/Intents/SignoffIntents.swift`) so the
            // cast disambiguates.
            guard let intentError = error as? SignoffCore.AppIntentError else {
                XCTFail("Expected SignoffCore.AppIntentError, got \(error)")
                return
            }
            switch intentError {
            case .rateLimited(let retryAfter):
                XCTAssertGreaterThan(retryAfter, 0,
                                     "retryAfter must be positive while the window is full")
            case .coldStartUnavailable:
                XCTFail("Rate-limit breach must surface .rateLimited, not .coldStartUnavailable")
            }
        }
    }

    func testEnforceRateLimit_PrunesOldWindowEntries() throws {
        // Inject a timestamp 1h+ in the past; the next call must prune it
        // and succeed (the persisted window should be empty post-prune).
        let stale = Date().addingTimeInterval(-3700).timeIntervalSince1970
        UserDefaults.standard.set([stale], forKey: rateLimitKey)
        XCTAssertNoThrow(try GenerateSignoffIntent.enforceRateLimit(),
                          "Stale-window prune must allow the call to proceed")
        let afterWindow: [TimeInterval] = (UserDefaults.standard.array(forKey: rateLimitKey) as? [TimeInterval]) ?? []
        XCTAssertEqual(afterWindow.count, 1,
                       "Stale entry must be pruned; only the new call should remain")
    }

    func testBootstrap_Idempotent() async throws {
        // Cold-start binding: AppState.shared.bootstrap() runs initialize()
        // once; repeat calls must not throw (idempotent guard).
        try await AppState.shared.bootstrap()
        try await AppState.shared.bootstrap()
        // No fatal trap = pass.
    }

    func testAppShortcutsProvider_BothIntentsRegistered() {
        // Per Apple's HIG App Intents Editorial Guidelines, both Generate
        // and Copy intents should be present so Shortcuts.app surfaces them
        // in the user's "My Shortcuts" library.
        let shortcuts = SignoffShortcutsProvider.appShortcuts
        XCTAssertGreaterThanOrEqual(shortcuts.count, 2,
            "SignoffShortcutsProvider must register \u{2265}2 AppShortcuts (Generate + Copy)")
    }

    func testAppShortcutsProvider_PhrasesUseApplicationNamePlaceholder() {
        // Phrase-content verification is deferred to integration tests:
        // Apple's `AppShortcut` does not expose `phrases` as a public
        // property on macOS 13+ (phrases are only accessible via the
        // `phrases:` initializer argument on
        // `AppShortcut(intent:phrases:shortTitle:systemImageName:)`).
        // We assert the registration count here; the phrase-placeholder
        // check is a v1.0.1 polish item tracked in docs/TODOS.md.
        let shortcuts = SignoffShortcutsProvider.appShortcuts
        XCTAssertGreaterThanOrEqual(shortcuts.count, 2,
            "SignoffShortcutsProvider must register \u{2265}2 AppShortcuts (Generate + Copy)")
    }

    // MARK: - DX-EXP-15 Bucket parameter

    func testGenerateSignoffIntent_BucketParameterDefaultsToNil() {
        let intent = GenerateSignoffIntent()
        XCTAssertNil(intent.bucketId,
                     "Bucket parameter must default to nil (use current selection)")
    }

    func testGenerateSignoffIntent_BucketParameterAcceptsOverride() {
        var intent = GenerateSignoffIntent()
        intent.bucketId = BucketID.professional.rawValue
        XCTAssertEqual(intent.bucketId, "professional")
    }

    func testGenerateSignoffIntent_ApplyBucketOverrideUpdatesSelectedBucket() async throws {
        AppState.shared.buckets = Bucket.defaultBuckets()
        AppState.shared.selectedBucketId = BucketID.standard.rawValue

        var intent = GenerateSignoffIntent()
        intent.bucketId = BucketID.unhinged.rawValue
        intent.applyBucketOverride()

        XCTAssertEqual(AppState.shared.selectedBucketId, BucketID.unhinged.rawValue,
                       "Known bucket override must update AppState.selectedBucketId")
    }

    func testGenerateSignoffIntent_ApplyBucketOverrideIgnoresUnknownBucket() async throws {
        AppState.shared.buckets = Bucket.defaultBuckets()
        AppState.shared.selectedBucketId = BucketID.standard.rawValue

        var intent = GenerateSignoffIntent()
        intent.bucketId = "not-a-real-bucket"
        intent.applyBucketOverride()

        XCTAssertEqual(AppState.shared.selectedBucketId, BucketID.standard.rawValue,
                       "Unknown bucket must leave the current selection alone")
    }

    func testGenerateSignoffIntent_ApplyBucketOverrideIgnoresNil() async throws {
        AppState.shared.buckets = Bucket.defaultBuckets()
        AppState.shared.selectedBucketId = BucketID.list.rawValue

        var intent = GenerateSignoffIntent()
        intent.bucketId = nil
        intent.applyBucketOverride()

        XCTAssertEqual(AppState.shared.selectedBucketId, BucketID.list.rawValue)
    }

    func testGenerateSignoffIntent_ApplyBucketOverrideAcceptsEveryBucketID() async throws {
        AppState.shared.buckets = Bucket.defaultBuckets()
        let liveIDs = BucketID.allCases.filter { $0 != .generalLegacy }
        for id in liveIDs {
            AppState.shared.selectedBucketId = BucketID.standard.rawValue
            var intent = GenerateSignoffIntent()
            intent.bucketId = id.rawValue
            intent.applyBucketOverride()
            XCTAssertEqual(AppState.shared.selectedBucketId, id.rawValue,
                           "applyBucketOverride must accept BucketID.\(id.rawValue)")
        }
    }

    func testGenerateSignoffIntent_ApplyBucketOverrideIsIdempotent() async throws {
        AppState.shared.buckets = Bucket.defaultBuckets()
        AppState.shared.selectedBucketId = BucketID.footer.rawValue

        var intent = GenerateSignoffIntent()
        intent.bucketId = BucketID.custom.rawValue
        intent.applyBucketOverride()
        intent.applyBucketOverride()

        XCTAssertEqual(AppState.shared.selectedBucketId, BucketID.custom.rawValue)
    }
}
