// Signposts.swift — stable instrumentation for SPEC §12 success criteria.
// Per PERFECTION_PLAN_V2_AUTOPLAN_REVIEW.md TASK-9 + DX EXPANSION TASK-21 (DX-EXP-10).

import Foundation
import os

/// Signpost intervals Apple Instruments recognizes across launches.
/// Instruments → Signoff scheme → "Signpost Timeline" lane.
public enum SignoffSignpost {
    /// Cold launch → menubar ready (SPEC §12 target <400ms).
    public static let coldLaunch = OSSignposter(subsystem: SignoffLog.subsystem, category: "cold-launch")

    /// ⌃⌘1 key received → first preview pill rendered (SPEC §12 target <150ms fallback).
    public static let generateFallback = OSSignposter(subsystem: SignoffLog.subsystem, category: "generate-fallback")

    /// Foundation Models round-trip (SPEC §12 target <2s FM).
    public static let generateProvider = OSSignposter(subsystem: SignoffLog.subsystem, category: "generate-provider")

    /// Paste commit (⌘C → ⌘V synthesis) — single cue per attempt.
    public static let pasteCommit = OSSignposter(subsystem: SignoffLog.subsystem, category: "paste-commit")

    /// Popover appear animation (SPEC §1.2 160ms ±20ms).
    public static let popoverAppear = OSSignposter(subsystem: SignoffLog.subsystem, category: "popover-appear")

    /// GenerationService dedupe lookups — frequent noise; lower log level.
    public static let dedupeHistory = OSSignposter(subsystem: SignoffLog.subsystem, category: "dedupe-history")

    /// Silent learning observations — VoiceProfile updates from AX events.
    public static let learning = OSSignposter(subsystem: SignoffLog.subsystem, category: "learning")

    /// One-line metrics emit for generate completions.
    /// Console: `log stream --predicate 'subsystem == "com.signoff" AND category == "metrics"'`
    public static func recordGenerateLatency(provider: GenerationProviderKind, latencyMs: Int) {
        SignoffLogLogger(.metrics).info(
            "generate provider=\(provider.rawValue, privacy: .public) latencyMs=\(latencyMs, privacy: .public)"
        )
    }
}

/// Round-tripped first-launch trace persisted to disk (DX-EXP-10).
/// Stored at `~/Library/Application Support/Signoff/first-run-trace.json`.
public enum FirstRunTrace: Sendable {

    public struct Entry: Codable, Equatable, Sendable {
        public let timestamp: Date
        public let stage: String
        public let note: String?
        public init(stage: String, note: String? = nil, timestamp: Date = Date()) {
            self.stage = stage
            self.note = note
            self.timestamp = timestamp
        }
    }

    /// Compute the on-disk URL inside the same execution context as the
    /// caller — nonisolated so Swift 6 strict-concurrency sees no Sendable
    /// crossing when the caller hands it off to a `Task.detached`.
    nonisolated public static func computeURL() -> URL {
        let fm = FileManager.default
        let support = try? fm.url(for: .applicationSupportDirectory,
                                  in: .userDomainMask,
                                  appropriateFor: nil,
                                  create: true)
        let dir = (support ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("Signoff", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("first-run-trace.json", isDirectory: false)
    }

    /// Legacy accessor: most callers read `FirstRunTrace.url` directly.
    /// Now a Sendable static computed lazily.
    nonisolated public static var url: URL { computeURL() }

    /// Append `entry` to the trace file. URL is computed inside the detached
    /// scope so MainActor isolation never crosses (fixes SigningClosureRisksDataRace).
    /// Async + serialized — never blocks the cold-launch critical path
    /// (DX-EXP-10 + ENG Review Perf Concern-1 fix).
    public static func record(_ entry: Entry) async {
        let payload = entry
        await Task.detached(priority: .utility) {
            let target = FirstRunTrace.computeURL()
            var existing: [Entry] = []
            if let data = try? Data(contentsOf: target),
               let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
                existing = decoded
            }
            existing.append(payload)
            if let encoded = try? JSONEncoder().encode(existing) {
                try? encoded.write(to: target, options: [.atomic])
            }
        }.value
    }
}
