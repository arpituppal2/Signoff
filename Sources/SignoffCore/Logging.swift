// Logging.swift — Signoff observability subsystem.
// Per PERFECTION_PLAN_V2_AUTOPLAN_REVIEW.md TASK-9 + CEO EXPANSION §Section 8.
// 5 subsystems, each scoped for OSLog filtering and Signpost timeline threading.

import Foundation
import os

/// Single source of truth for Signoff's os.Logger subsystem + category names.
/// Every log call site uses these symbols — never free-form subsystem strings.
public enum SignoffLog {

    /// Bundle identifier. Matches the host's `CFBundleIdentifier` so
    /// `log stream --predicate 'subsystem == "com.signoff"'` filters cleanly.
    public static let subsystem = "com.signoff"

    /// Subsystem categories per SPEC §8.1 + CEO EXPANSION §Section 8.
    public enum Category: String, CaseIterable {
        case generation      // GenerationService, providers, post-processing
        case shortcuts       // CarbonEventTap, PasteAutomation, ShortcutManager

        case persistence     // SwiftData, Migrations, Bucket/Generation records
        case ui              // Popover, Settings, Onboarding, Brand
        case metrics         // MetricKit hang/crash/CPU telemetry
        case learning        // SilentLearningEngine, VoiceProfile learning

        public var osLogCategory: String { rawValue }
    }
}

/// Convenience accessor — call sites stay terse:
///     `SignoffLog.logger(for: .generation).info("…")`
public func SignoffLogLogger(_ category: SignoffLog.Category) -> Logger {
    Logger(subsystem: SignoffLog.subsystem, category: category.osLogCategory)
}

/// Stable handle for modules that want a single cached logger rather than
/// constructing per-call sites (e.g. AppState).
public func SignoffCachedLogger(_ category: SignoffLog.Category) -> Logger {
    Logger(subsystem: SignoffLog.subsystem, category: category.osLogCategory)
}
