import Foundation
import SwiftData
import os

/// Owns the SwiftData stack and seeds default values on first launch.
/// Performs the v1→v2 "general" → "standard" pre-migration before opening the
/// store (§14.2.1 of the spec; idempotent).
///
/// Store open is soft-fail: primary → quarantine+retry clean → in-memory.
/// Never `fatalError` on a corrupt store (signoff-v2-spec §15 recovery table).
/// Soft-fail recovery path surfaced to AppState / popover ErrorFixCard.
public enum StoreRecovery: Equatable, Sendable {
    /// Durable store was quarantined and a clean on-disk store opened.
    case resetCorruptStore
    /// Durable open failed; running on ephemeral in-memory store.
    case inMemoryFallback

    public var userMessage: String {
        switch self {
        case .resetCorruptStore:
            return "Local history was reset after a store recovery."
        case .inMemoryFallback:
            return "Local history is temporarily unavailable — Signoff is running without saving."
        }
    }
}

@MainActor
public final class PersistenceController: @unchecked Sendable {
    public static let shared = PersistenceController()

    public let container: ModelContainer
    public let context: ModelContext

    /// True when the durable store failed and we opened a replacement (clean
    /// disk store or ephemeral in-memory). UI should surface a one-shot banner.
    public private(set) var recoveredFromStoreFailure: Bool = false
    /// True when running on an in-memory store (history will not persist).
    public private(set) var isEphemeral: Bool = false
    public private(set) var lastStoreErrorDescription: String?

    /// Derived from bootstrap flags for one-shot UI recovery cards.
    public var storeRecovery: StoreRecovery? {
        guard recoveredFromStoreFailure else { return nil }
        return isEphemeral ? .inMemoryFallback : .resetCorruptStore
    }

    /// Preview / test factory — always in-memory, never touches disk.
    public static func inMemory() -> PersistenceController {
        PersistenceController(inMemoryOnly: true)
    }

    public init(inMemoryOnly: Bool = false) {
        let schema = Self.makeSchema()
        let bootstrap = Self.bootstrap(schema: schema, inMemoryOnly: inMemoryOnly)
        self.container = bootstrap.container
        self.context = bootstrap.context
        self.recoveredFromStoreFailure = bootstrap.recovered
        self.isEphemeral = bootstrap.ephemeral
        self.lastStoreErrorDescription = bootstrap.errorDescription
    }

    private struct Bootstrap {
        let container: ModelContainer
        let context: ModelContext
        let recovered: Bool
        let ephemeral: Bool
        let errorDescription: String?
    }

    private static func bootstrap(schema: Schema, inMemoryOnly: Bool) -> Bootstrap {
        if inMemoryOnly {
            do {
                let opened = try open(schema: schema, mode: .inMemory)
                return Bootstrap(
                    container: opened.container,
                    context: opened.context,
                    recovered: false,
                    ephemeral: true,
                    errorDescription: nil
                )
            } catch {
                SignoffLogLogger(.persistence).fault(
                    "In-memory SwiftData open failed: \(String(describing: error), privacy: .public)"
                )
                preconditionFailure(
                    "PersistenceController: unable to open in-memory SwiftData store: \(error)"
                )
            }
        }

        MigrationPreScan.rewriteLegacyIDsIfNeeded()

        do {
            let opened = try open(schema: schema, mode: .durable)
            return Bootstrap(
                container: opened.container,
                context: opened.context,
                recovered: false,
                ephemeral: false,
                errorDescription: nil
            )
        } catch {
            let primaryError = String(describing: error)
            SignoffLogLogger(.persistence).error(
                "Primary SwiftData store failed; quarantining and retrying: \(primaryError, privacy: .public)"
            )
            quarantineStoreFiles()

            do {
                let opened = try open(schema: schema, mode: .durable)
                return Bootstrap(
                    container: opened.container,
                    context: opened.context,
                    recovered: true,
                    ephemeral: false,
                    errorDescription: primaryError
                )
            } catch {
                let cleanError = String(describing: error)
                SignoffLogLogger(.persistence).error(
                    "Clean store retry failed; falling back to in-memory: \(cleanError, privacy: .public)"
                )
                do {
                    let opened = try open(schema: schema, mode: .inMemory)
                    return Bootstrap(
                        container: opened.container,
                        context: opened.context,
                        recovered: true,
                        ephemeral: true,
                        errorDescription: cleanError
                    )
                } catch {
                    SignoffLogLogger(.persistence).fault(
                        "In-memory fallback also failed: \(String(describing: error), privacy: .public)"
                    )
                    preconditionFailure(
                        "PersistenceController: unable to open any SwiftData store (including in-memory): \(error)"
                    )
                }
            }
        }
    }

    private enum StoreMode {
        case durable
        case inMemory
    }

    private struct OpenedStore {
        let container: ModelContainer
        let context: ModelContext
    }

    private static func makeSchema() -> Schema {
        Schema([
            Bucket.self,
            SignoffGeneration.self,
            UserProfile.self,
            AppSettings.self,
            VoiceProfile.self,
        ])
    }

    private static func open(schema: Schema, mode: StoreMode) throws -> OpenedStore {
        let config: ModelConfiguration
        switch mode {
        case .inMemory:
            config = ModelConfiguration(
                "Signoff",
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        case .durable:
            config = ModelConfiguration(
                schema: schema,
                url: storeURL(),
                cloudKitDatabase: .none
            )
        }
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        context.autosaveEnabled = true
        return OpenedStore(container: container, context: context)
    }

    /// Canonical on-disk store URL under Application Support.
    public static func storeURL() -> URL {
        let fm = FileManager.default
        let dir = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Signoff", isDirectory: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Signoff", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Signoff.store")
    }

    /// Move corrupt store (+ sidecar) aside so a clean open can succeed.
    static func quarantineStoreFiles() {
        let fm = FileManager.default
        let primary = storeURL()
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let candidates = [
            primary,
            URL(fileURLWithPath: primary.path + "-shm"),
            URL(fileURLWithPath: primary.path + "-wal"),
        ]
        for url in candidates where fm.fileExists(atPath: url.path) {
            let dest = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).corrupt-\(stamp)")
            do {
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.moveItem(at: url, to: dest)
                SignoffLogLogger(.persistence).info(
                    "Quarantined store file to \(dest.lastPathComponent, privacy: .public)"
                )
            } catch {
                SignoffLogLogger(.persistence).error(
                    "Failed to quarantine \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)"
                )
                // Best-effort delete so retry can create a fresh file.
                try? fm.removeItem(at: url)
            }
        }
    }

    public func initializeDefaultsIfNeeded() throws {
        try ensureSettings()
        try ensureProfile()
        try ensureBuckets()
    }

    public func ensureSettings() throws {
        let descriptor = FetchDescriptor<AppSettings>()
        let existing = try context.fetch(descriptor)
        if existing.isEmpty {
            let s = AppSettings()
            context.insert(s)
            try context.save()
        }
    }

    public func ensureProfile() throws {
        let descriptor = FetchDescriptor<UserProfile>()
        let existing = try context.fetch(descriptor)
        if existing.isEmpty {
            context.insert(UserProfile.makeEmpty())
            try context.save()
        }
    }

    public func ensureBuckets() throws {
        let descriptor = FetchDescriptor<Bucket>()
        let existing = try context.fetch(descriptor)
        if existing.isEmpty {
            for bucket in Bucket.defaultBuckets() {
                context.insert(bucket)
            }
            try context.save()
        }
    }

    public func fetchSettings() throws -> AppSettings {
        try context.fetch(FetchDescriptor<AppSettings>()).first ?? AppSettings()
    }

    public func fetchProfile() throws -> UserProfile? {
        try context.fetch(FetchDescriptor<UserProfile>()).first
    }

    /// Insert-or-update the profile row. Used by onboarding ProfileStep after
    /// the user edits the in-memory copies and we reconcile against the store.
    public func saveProfile(_ profile: UserProfile) throws {
        if let existing = try fetchProfile() {
            existing.name = profile.name
            existing.title = profile.title
            existing.company = profile.company
            existing.email = profile.email
            existing.phone = profile.phone
            existing.website = profile.website
            existing.linkedin = profile.linkedin
            existing.selfDescription = profile.selfDescription
            if existing.emojiEnabled != profile.emojiEnabled {
                existing.emojiEnabled = profile.emojiEnabled
            }
            try context.save()
        } else {
            context.insert(profile)
            try context.save()
        }
    }

    public func fetchEnabledBuckets() throws -> [Bucket] {
        let descriptor = FetchDescriptor<Bucket>(sortBy: [SortDescriptor(\.sortOrder)])
        let all = try context.fetch(descriptor)
        return all.filter { $0.isEnabled }
    }

    public func fetchGenerations(limit: Int = 50) throws -> [SignoffGeneration] {
        var descriptor = FetchDescriptor<SignoffGeneration>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    public func recordGeneration(bucketId: String,
                                  text: String,
                                  providerRaw: String,
                                  latencyMs: Int) async {
        let g = SignoffGeneration(bucketId: bucketId,
                                   text: text,
                                   latencyMs: latencyMs,
                                   providerRaw: providerRaw)
        context.insert(g)
        try? context.save()
        // Keep AppState.recentGenerations live — previously only refreshed at
        // initialize(), so History/Copy-last stayed stale after each generate.
        AppState.shared.refreshRecentGenerations()
    }

    public func updateBucket(_ bucket: Bucket) throws {
        bucket.updatedAt = Date()
        try context.save()
    }

    public func toggleFavorite(_ generation: SignoffGeneration) throws {
        generation.isFavorite.toggle()
        try context.save()
    }

    // MARK: - VoiceProfile

    public func fetchVoiceProfile() throws -> VoiceProfile? {
        try context.fetch(FetchDescriptor<VoiceProfile>()).first
    }

    public func saveVoiceProfile(_ profile: VoiceProfile) throws {
        if let existing = try fetchVoiceProfile() {
            // Update existing
            existing.qualityLexicalFingerprintData = profile.qualityLexicalFingerprintData
            existing.noiseLexicalFingerprintData = profile.noiseLexicalFingerprintData
            existing.qualityAvgSentenceLength = profile.qualityAvgSentenceLength
            existing.qualityPunctuationStyleData = profile.qualityPunctuationStyleData
            existing.qualityFormalityScore = profile.qualityFormalityScore
            existing.qualityEmojiFrequency = profile.qualityEmojiFrequency
            existing.qualityVocabularyRichness = profile.qualityVocabularyRichness
            existing.adoptedSignoffPatternsData = profile.adoptedSignoffPatternsData
            existing.rejectedSignoffPatternsData = profile.rejectedSignoffPatternsData
            existing.contextQualityWeightsData = profile.contextQualityWeightsData
            existing.lastUpdated = profile.lastUpdated
            existing.version = profile.version
            existing.totalQualityObservations = profile.totalQualityObservations
            existing.totalNoiseObservations = profile.totalNoiseObservations
            existing.isLearningPaused = profile.isLearningPaused
            existing.learningConsentGranted = profile.learningConsentGranted
            existing.observedAppsData = profile.observedAppsData
            try context.save()
        } else {
            context.insert(profile)
            try context.save()
        }
    }

    public func initializeVoiceProfile() throws {
        let descriptor = FetchDescriptor<VoiceProfile>()
        let existing = try context.fetch(descriptor)
        if existing.isEmpty {
            let vp = VoiceProfile()
            context.insert(vp)
            try context.save()
        }
    }

}
