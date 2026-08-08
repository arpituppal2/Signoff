import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
/// Per-bucket warm `LanguageModelSession` pool. Sessions keep stable
/// Instructions so `prewarm(promptPrefix:)` can cache the common prefix;
/// per-request user data stays in the Prompt only.
@available(macOS 26, *)
public actor FoundationModelsSessionPool {
    public static let shared = FoundationModelsSessionPool()

    private struct Entry {
        let instructionsFingerprint: String
        let session: LanguageModelSession
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    /// Eagerly load model assets for a bucket. No-op when the session is
    /// already responding (Apple forbids overlapping prewarm/respond).
    public func prewarm(bucketId: String, instructions: String, promptPrefix: String?) {
        let session = session(for: bucketId, instructions: instructions)
        guard !session.isResponding else { return }
        let prefix: Prompt? = promptPrefix.map { Prompt($0) }
        session.prewarm(promptPrefix: prefix)
    }

    /// Generate a guided `SignoffOutput`. Retries once on a fresh session when
    /// the transcript exceeds the context window.
    public func respond(
        bucketId: String,
        instructions: String,
        prompt: String,
        options: GenerationOptions = GenerationOptions(temperature: 0.7, maximumResponseTokens: 64)
    ) async throws -> SignoffOutput {
        // Always create a fresh session to avoid content filter state issues
        let session = makeSession(instructions: instructions)

        do {
            let response = try await session.respond(
                to: prompt,
                generating: SignoffOutput.self,
                options: options
            )
            return response.content
        } catch let error as LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = error {
                let fresh = makeSession(instructions: instructions)
                entries[bucketId] = Entry(
                    instructionsFingerprint: fingerprint(instructions),
                    session: fresh
                )
                let response = try await fresh.respond(
                    to: prompt,
                    generating: SignoffOutput.self,
                    options: options
                )
                return response.content
            }
            throw mapGenerationError(error)
        }
    }

    public func invalidate(bucketId: String) {
        entries.removeValue(forKey: bucketId)
    }

    public func invalidateAll() {
        entries.removeAll(keepingCapacity: true)
    }

    // MARK: - Internals

    private func session(for bucketId: String, instructions: String) -> LanguageModelSession {
        let fp = fingerprint(instructions)
        if let existing = entries[bucketId], existing.instructionsFingerprint == fp {
            return existing.session
        }
        let created = makeSession(instructions: instructions)
        entries[bucketId] = Entry(instructionsFingerprint: fp, session: created)
        return created
    }

    private func makeSession(instructions: String) -> LanguageModelSession {
        // String is InstructionsRepresentable; this matches Apple's session API
        // and the prior (working) Signoff call shape.
        LanguageModelSession(instructions: instructions)
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
#endif
