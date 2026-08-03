import Foundation
import os

/// Lightweight, **DEBUG-only** instrumention for on-device generation.
///
/// The onboarding interactive demos claim a real Apple Foundation Models call
/// is running. This probe makes that verifiable: it records a structured event
/// per generation (cache hit vs live, provider, latency, status) to an
/// `os.Logger` line and exposes a tiny developer-visible status string that the
/// onboarding footer surfaces in debug builds.
///
/// Everything is `#if DEBUG` gated — release builds pay zero cost (no logging,
/// no `@Published` churn) and ship no instrumentation surface.
@MainActor
public final class GenerationDebugProbe: ObservableObject {
    public static let shared = GenerationDebugProbe()

    /// Last human-readable event (e.g. "live fmf: unhinged ok 312ms").
    /// Empty in release — the `@Published` only mutates under DEBUG.
    @Published public private(set) var lastEvent: String = ""
    /// True when the on-device Apple Foundation Model last probed as ready.
    @Published public private(set) var modelActive: Bool = false

    private let log = Logger(subsystem: "app.signoff.generation", category: "debug-probe")

    /// Cap on the stored event string so it never grows beyond a status line.
    private let maxEventLen = 120

    public func recordEvent(_ event: String) {
        #if DEBUG
        let trimmed = event.count > maxEventLen
            ? String(event.prefix(maxEventLen - 1)) + "…"
            : event
        log.info("🔢 \(trimmed, privacy: .public)")
        lastEvent = trimmed
        #endif
    }

    public func setModelActive(_ active: Bool) {
        #if DEBUG
        modelActive = active
        #endif
    }

    /// One-line status for the DEBUG onboarding footer.
    public var statusString: String {
        #if DEBUG
        return modelActive ? "On-device model active" : "Model unavailable"
        #else
        return ""
        #endif
    }
}
