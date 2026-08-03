import AppIntents
import Foundation

/// Two `-init` lightweight AppIntents + an `AppShortcutsProvider` so power users
/// can drive Signoff from the macOS Shortcuts app. Per Apple HIG "App Shortcuts"
/// doc, macOS does NOT surface these as system "App Shortcuts" the way iOS does
/// — the spotlight here is the Shortcuts.app gallery & developer automation,
/// not Siri. (iOS App-Shortcut phrases live in the `phrases:` array for future
/// cross-platform parity if/when Signoff ships on iPhone.)
///
/// `perform()` is `@MainActor` because `AppState.shared.generateNow()` and
/// `AppState.shared.copyMostRecent()` are MainActor-isolated @Published mutators
/// — hopping through MainActor here matches the same anti-pattern that the
/// eng review flagged elsewhere: a one-time MainActor hop at invocation, never
/// a `Task { @MainActor in … }` inside the closure.
///
/// **PF-bundle (per PERFECTION_PLAN_V2_AUTOPLAN_REVIEW.md TASK-12/13):**
///  • (TASK-12) rate-limit guard: cap at 30 generations/hour from AppIntents path.
///  • (TASK-13) cold-start guard: await `AppState.bootstrap()` so the singleton
///    is fully wired (`initialize()`: persistence defaults, buckets, history,
///    generation→persistence attach) before we mutate it. Closes the 🛑 race
///    called out in the GSTACK report (where a `Task { @MainActor in }` hop
///    was the prior silent-fail pattern).
@available(macOS 13.0, *)
public struct GenerateSignoffIntent: AppIntent {
    // `static let` (not `static var`) — Swift 6 StrictConcurrency treats `static var`
    // as global-mutable shared state and rejects it under the build flag set in
    // Package.swift. The AppIntent protocol requires `title` to be a property
    // (not a constant initializer), so we keep the property form and rely on
    // `let` to satisfy the concurrency checker. `IntentDescription(...)` is
    // a Sendable value type so this is safe.
    public static let title: LocalizedStringResource = "Generate Signoff"
    public static let description = IntentDescription(
        "Write a signoff using the currently selected bucket and paste it at the cursor.",
        categoryName: "Signoff"
    )

    /// DX-EXP-15 Bucket intent parameter. Power users invoke from
    /// Shortcuts.app with an explicit bucket override; falls back to
    /// the currently-selected bucket when nil.
    @Parameter(title: "Bucket", default: nil)
    public var bucketId: String?

    /// TASK-12: rate-limit guard. Persisted in UserDefaults totals across launch
    /// boundaries so a user who force-quits + relaunches can't bypass the cap.
    private static let rateLimitKey = "SignoffIntent.generate.window"
    private static let rateLimitWindow: TimeInterval = 60 * 60               // 1 hour
    private static let rateLimitMax: Int = 30                                // 30/hr

    /// TASK-13: cold-start guard. `bootstrap()` runs idempotent `initialize()`
    /// so Shortcuts.app launches get a warm store before generate/copy.
    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        // TASK-13: cold-start binding.
        try await AppState.shared.bootstrap()

        // TASK-12: rate-limit guard (static method — Swift requires `Self.` to
        // disambiguate from any future instance-method shadowing on
        // AppIntent.perform()).
        try Self.enforceRateLimit()

        // DX-EXP-15: apply optional bucket override before generate.
        // Falls back to the currently selected bucket when nil / unknown.
        applyBucketOverride()

        await AppState.shared.generateNow()
        return .result()
    }

    /// Applies `bucketId` onto `AppState.selectedBucketId` when Shortcuts
    /// supplied a known bucket. Package-visible so unit tests can assert the
    /// parameter without booting the full generate → paste pipeline.
    @MainActor
    func applyBucketOverride() {
        guard let bucketId,
              AppState.shared.buckets.contains(where: { $0.id == bucketId }) else {
            return
        }
        AppState.shared.selectedBucketId = bucketId
    }

    /// Roll a 1-hour sliding window, prune entries older than the threshold,
    /// then check `remaining > 0`. On breach, throw an `AppIntentError` so
    /// Shortcuts.app surfaces the failure rather than silently no-oping.
    static func enforceRateLimit(now: Date = Date()) throws {
        let defaults = UserDefaults.standard
        var window: [TimeInterval] = (defaults.array(forKey: rateLimitKey) as? [TimeInterval]) ?? []
        let cutoff = now.timeIntervalSince1970 - rateLimitWindow
        window.removeAll { $0 < cutoff }
        guard window.count < rateLimitMax else {
            throw AppIntentError.rateLimited(
                retryAfter: rateLimitWindow - (now.timeIntervalSince1970 - (window.first ?? now.timeIntervalSince1970))
            )
        }
        window.append(now.timeIntervalSince1970)
        defaults.set(window, forKey: rateLimitKey)
    }
}

/// Distinct error type so AppIntents error UX can branch on it specifically.
public enum AppIntentError: Error, LocalizedError {
    case rateLimited(retryAfter: TimeInterval)
    case coldStartUnavailable

    public var errorDescription: String? {
        switch self {
        case .rateLimited(let retryAfter):
            let minutes = Int(retryAfter / 60)
            return "Signoff rate limit reached. Try again in \(minutes) minutes."
        case .coldStartUnavailable:
            return "Signoff is starting up; please retry in a moment."
        }
    }
}

@available(macOS 13.0, *)
public struct CopyLastSignoffIntent: AppIntent {
    public static let title: LocalizedStringResource = "Copy Last Signoff"
    public static let description = IntentDescription(
        "Copy the most recent signoff to the macOS clipboard.",
        categoryName: "Signoff"
    )

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        // TASK-13: cold-start binding (same as GenerateSignoffIntent).
        try await AppState.shared.bootstrap()
        AppState.shared.copyMostRecent()
        return .result()
    }
}

/// Provider that registers each intent with the system so it shows up in
/// Shortcuts.app → "My Shortcuts". Editor's note: `appShortcuts` is meant for
/// iOS-style system-level suggestions; on macOS the array is harmless and
/// keeps cross-platform future-proofing in place.
@available(macOS 13.0, *)
public struct SignoffShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GenerateSignoffIntent(),
            phrases: [
                "Generate a signoff in \(.applicationName)",
                "Write a signoff in \(.applicationName)"
            ],
            shortTitle: "Generate Signoff",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: CopyLastSignoffIntent(),
            phrases: [
                "Copy last signoff in \(.applicationName)",
                "Copy my last signoff in \(.applicationName)"
            ],
            shortTitle: "Copy Last",
            systemImageName: "doc.on.doc"
        )
    }
}
