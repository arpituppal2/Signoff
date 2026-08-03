import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
/// Prewarm cache for Foundation Model assets. Does NOT reuse sessions for
/// generation — each `respond` call creates a fresh session to avoid transcript
/// pollution across independent generations. The prewarm cache only stores
/// pre-warmed sessions per (bucket, instructions) to warm model assets.
@available(macOS 26, *)
public actor FoundationModelsSessionPool {
    public static let shared = FoundationModelsSessionPool()

    private struct PrewarmedEntry {
        let session: any LanguageModelSessionProtocol
        let instructionsFingerprint: String
        let bucketId: String
    }

    private var prewarmedEntries: [String: PrewarmedEntry] = [:]

    // Allow dependency injection for testing
    nonisolated(unsafe) static var sessionFactory: @Sendable (String) -> any LanguageModelSessionProtocol = { instructions in
        RealLanguageModelSession(instructions: instructions)
    }

    // Foundation Models appears to have a system-level concurrency limit.
    // Serialize all FMF generations to avoid rejection of concurrent requests.
    private var generationInProgress = false

    public init() {}

    /// Eagerly load model assets for a bucket. Creates a session and prewarms it
    /// with the common prompt prefix. Does not store for re-use in generation.
    public func prewarm(bucketId: String, instructions: String, promptPrefix: String?) async {
        let fp = fingerprint(instructions)
        let key = "\(bucketId)|\(fp)"

        // If already prewarmed with same fingerprint, skip
        if let existing = prewarmedEntries[key], existing.instructionsFingerprint == fp {
            let isResponding = await existing.session.isResponding
            guard !isResponding else { return }
            let prefix: Prompt? = promptPrefix.map { Prompt($0) }
            await existing.session.prewarm(promptPrefix: prefix)
            return
        }

        // Create and prewarm new session
        let session = makeSession(instructions: instructions)
        let isResponding = await session.isResponding
        guard !isResponding else { return }
        let prefix: Prompt? = promptPrefix.map { Prompt($0) }
        await session.prewarm(promptPrefix: prefix)
        prewarmedEntries[key] = PrewarmedEntry(
            session: session,
            instructionsFingerprint: fp,
            bucketId: bucketId
        )
    }

    /// Generate a guided `SignoffOutput` using a FRESH session each time.
    /// This avoids transcript pollution between independent generations.
    /// Retries once on a fresh session when the transcript exceeds the context window.
    /// Serializes FMF generations (system appears to reject concurrent requests).
    public func respond(
        bucketId: String,
        instructions: String,
        prompt: String,
        options: GenerationOptions = GenerationOptions(temperature: 0.7, maximumResponseTokens: 48)
    ) async throws -> SignoffOutput {
        // Serialize FMF generations to avoid system concurrency rejections
        while generationInProgress {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
        generationInProgress = true
        defer { generationInProgress = false }

        // ALWAYS create a fresh session for generation to avoid conversation
        // history leaking between independent generations.
        let session = makeSession(instructions: instructions)

        do {
            let output: SignoffOutput = try await session.respond(
                to: prompt,
                generating: SignoffOutput.self,
                options: options
            )
            return output
        } catch let error as LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = error {
                // Retry once with another fresh session
                let fresh = makeSession(instructions: instructions)
                let output: SignoffOutput = try await fresh.respond(
                    to: prompt,
                    generating: SignoffOutput.self,
                    options: options
                )
                return output
            }
            throw mapGenerationError(error)
        }
    }

    public func invalidate(bucketId: String) {
        // Remove all prewarmed entries for this bucket
        prewarmedEntries = prewarmedEntries.filter { $0.value.bucketId != bucketId }
    }

    public func invalidateAll() {
        prewarmedEntries.removeAll(keepingCapacity: true)
    }

    // MARK: - Internals

    private func makeSession(instructions: String) -> any LanguageModelSessionProtocol {
        Self.sessionFactory(instructions)
    }

    private func fingerprint(_ instructions: String) -> String {
        instructions
    }

    private func mapGenerationError(_ error: LanguageModelSession.GenerationError) -> GenerationError {
        // Associated-value payloads are ignored — we only need the case for
        // Signoff's GenerationError taxonomy.
        switch error {
        case .guardrailViolation(_):
            return .guardrailViolation(reason: error.localizedDescription)
        case .refusal(_, _):
            return .refused(reason: error.localizedDescription)
        case .exceededContextWindowSize(_):
            return .contextWindowExceeded
        case .assetsUnavailable(_):
            return .unavailable(reason: "Foundation Models assets unavailable")
        case .rateLimited(_):
            return .quotaBlocked(reason: "Foundation Models rate limited")
        case .concurrentRequests(_):
            return .unavailable(reason: "Foundation Models session busy")
        case .decodingFailure(_):
            return .unsafeCandidate(reason: "failed to decode SignoffOutput")
        case .unsupportedGuide(_), .unsupportedLanguageOrLocale(_):
            return .unavailable(reason: error.localizedDescription)
        @unknown default:
            return .unavailable(reason: error.localizedDescription)
        }
    }
}

// MARK: - Testing Support

@available(macOS 26, *)
public extension FoundationModelsSessionPool {
    /// Replace the session factory for testing. Call `resetSessionFactory()`
    /// after the test to restore the default.
    static func setSessionFactory(_ factory: @Sendable @escaping (String) -> any LanguageModelSessionProtocol) {
        sessionFactory = factory
    }

    /// Restore the default session factory (real Foundation Models session).
    static func resetSessionFactory() {
        sessionFactory = { instructions in
            RealLanguageModelSession(instructions: instructions)
        }
    }
}
#endif
