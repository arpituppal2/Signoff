import Testing
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
/// setup/teardown to prevent cross-test bleed.
@MainActor
struct AppIntentsTests {

    private let rateLimitKey = "SignoffIntent.generate.window"

    init() {
        // Reset rate limit state before each test
        UserDefaults.standard.removeObject(forKey: rateLimitKey)
    }

    @Test("Enforce rate limit allows first call")
    func enforceRateLimitAllowsFirstCall() async throws {
        // Cold start: empty window, first call must not throw.
        #expect(throws: Never.self) {
            try GenerateSignoffIntent.enforceRateLimit()
        }
    }

    @Test("Enforce rate limit allows 30 calls in window")
    func enforceRateLimitAllows30CallsInWindow() async throws {
        // Per production `static let rateLimitMax: Int = 30`. 30 calls in a
        // single window must all succeed.
        for _ in 0..<30 {
            try GenerateSignoffIntent.enforceRateLimit()
        }
    }

    @Test("Enforce rate limit throws on 31st call")
    func enforceRateLimitThrowsOn31stCall() async throws {
        // Saturate the window.
        for _ in 0..<30 {
            try? GenerateSignoffIntent.enforceRateLimit()
        }

        // 31st call must throw rateLimited
        #expect(throws: SignoffCore.AppIntentError.self) {
            try GenerateSignoffIntent.enforceRateLimit()
        }
    }

    @Test("Enforce rate limit prunes old window entries")
    func enforceRateLimitPrunesOldWindowEntries() async throws {
        // Inject a timestamp 1h+ in the past; the next call must prune it
        // and succeed (the persisted window should be empty post-prune).
        let stale = Date().addingTimeInterval(-3700).timeIntervalSince1970
        UserDefaults.standard.set([stale], forKey: rateLimitKey)

        #expect(throws: Never.self) {
            try GenerateSignoffIntent.enforceRateLimit()
        }

        let afterWindow: [TimeInterval] = (UserDefaults.standard.array(forKey: rateLimitKey) as? [TimeInterval]) ?? []
        #expect(afterWindow.count == 1, "Stale entry must be pruned; only the new call should remain")
    }

    @Test("Bootstrap is idempotent")
    func bootstrapIdempotent() async throws {
        // Cold-start binding: AppState.shared.bootstrap() runs initialize()
        // once; repeat calls must not throw (idempotent guard).
        try await AppState.shared.bootstrap()
        try await AppState.shared.bootstrap()
        // No fatal trap = pass.
    }

    @Test("AppShortcutsProvider registers both intents")
    func appShortcutsProviderBothIntentsRegistered() {
        // Per Apple's HIG App Intents Editorial Guidelines, both Generate
        // and Copy intents should be present so Shortcuts.app surfaces them
        // in the user's "My Shortcuts" library.
        let shortcuts = SignoffShortcutsProvider.appShortcuts
        #expect(shortcuts.count >= 2, "SignoffShortcutsProvider must register ≥2 AppShortcuts (Generate + Copy)")
    }

    @Test("AppShortcutsProvider phrases use application name placeholder")
    func appShortcutsProviderPhrasesUseApplicationNamePlaceholder() {
        // Phrase-content verification is deferred to integration tests:
        // Apple's `AppShortcut` does not expose `phrases` as a public
        // property on macOS 13+ (phrases are only accessible via the
        // `phrases:` initializer argument on
        // `AppShortcut(intent:phrases:shortTitle:systemImageName:)`).
        // We assert the registration count here; the phrase-placeholder
        // check is a v1.0.1 polish item tracked in docs/TODOS.md.
        let shortcuts = SignoffShortcutsProvider.appShortcuts
        #expect(shortcuts.count >= 2, "SignoffShortcutsProvider must register ≥2 AppShortcuts (Generate + Copy)")
    }

    // MARK: - DX-EXP-15 Bucket parameter

    @Test("GenerateSignoffIntent bucket parameter defaults to nil")
    func generateSignoffIntentBucketParameterDefaultsToNil() {
        let intent = GenerateSignoffIntent()
        #expect(intent.bucketId == nil, "Bucket parameter must default to nil (use current selection)")
    }

    @Test("GenerateSignoffIntent bucket parameter accepts override")
    func generateSignoffIntentBucketParameterAcceptsOverride() {
        let intent = GenerateSignoffIntent()
        intent.bucketId = BucketID.professional.rawValue
        #expect(intent.bucketId == "professional")
    }

    @Test("GenerateSignoffIntent applyBucketOverride updates selected bucket")
    func generateSignoffIntentApplyBucketOverrideUpdatesSelectedBucket() async throws {
        AppState.shared.buckets = Bucket.defaultBuckets()
        AppState.shared.selectedBucketId = BucketID.standard.rawValue

        let intent = GenerateSignoffIntent()
        intent.bucketId = BucketID.unhinged.rawValue
        intent.applyBucketOverride()

        #expect(AppState.shared.selectedBucketId == BucketID.unhinged.rawValue,
                "Known bucket override must update AppState.selectedBucketId")
    }

    @Test("GenerateSignoffIntent applyBucketOverride ignores unknown bucket")
    func generateSignoffIntentApplyBucketOverrideIgnoresUnknownBucket() async throws {
        AppState.shared.buckets = Bucket.defaultBuckets()
        AppState.shared.selectedBucketId = BucketID.standard.rawValue

        let intent = GenerateSignoffIntent()
        intent.bucketId = "not-a-real-bucket"
        intent.applyBucketOverride()

        #expect(AppState.shared.selectedBucketId == BucketID.standard.rawValue,
                "Unknown bucket must leave the current selection alone")
    }

    @Test("GenerateSignoffIntent applyBucketOverride ignores nil")
    func generateSignoffIntentApplyBucketOverrideIgnoresNil() async throws {
        AppState.shared.buckets = Bucket.defaultBuckets()
        AppState.shared.selectedBucketId = BucketID.standard.rawValue

        let intent = GenerateSignoffIntent()
        intent.bucketId = nil
        intent.applyBucketOverride()

        #expect(AppState.shared.selectedBucketId == BucketID.standard.rawValue)
    }

    @Test("GenerateSignoffIntent applyBucketOverride accepts every BucketID")
    func generateSignoffIntentApplyBucketOverrideAcceptsEveryBucketID() async throws {
        AppState.shared.buckets = Bucket.defaultBuckets()
        let liveIDs = Bucket.defaultBuckets().map(\.id)
        for id in liveIDs {
            AppState.shared.selectedBucketId = BucketID.standard.rawValue
            let intent = GenerateSignoffIntent()
            intent.bucketId = id
            intent.applyBucketOverride()
            #expect(AppState.shared.selectedBucketId == id,
                          "applyBucketOverride must accept BucketID.\(id)")
        }
    }

    @Test("GenerateSignoffIntent applyBucketOverride is idempotent")
    func generateSignoffIntentApplyBucketOverrideIsIdempotent() async throws {
        AppState.shared.buckets = Bucket.defaultBuckets()
        AppState.shared.selectedBucketId = BucketID.standard.rawValue

        let intent = GenerateSignoffIntent()
        intent.bucketId = BucketID.unhinged.rawValue
        intent.applyBucketOverride()
        intent.applyBucketOverride()

        #expect(AppState.shared.selectedBucketId == BucketID.unhinged.rawValue)
    }
}