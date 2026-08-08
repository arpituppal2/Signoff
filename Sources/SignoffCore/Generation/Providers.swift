import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Context passed to every provider so FMF / bundled share one composed prompt.
@available(macOS 26, *)
public struct ProviderGenerateContext: Sendable {
    public let bucketId: String
    public let template: PromptTemplate
    public let composed: PromptComposer.Composed
    public let unhingedLevel: UnhingedLevel?
    public let toneValue: Double?
    public let guardWords: [String]

    public init(bucketId: String,
                template: PromptTemplate,
                composed: PromptComposer.Composed,
                unhingedLevel: UnhingedLevel? = nil,
                toneValue: Double? = nil,
                guardWords: [String] = []) {
        self.bucketId = bucketId
        self.template = template
        self.composed = composed
        self.unhingedLevel = unhingedLevel
        self.toneValue = toneValue
        self.guardWords = guardWords
    }
}

/// Single provider surface for FMF / mocks.
@available(macOS 26, *)
public protocol GenerationProvider: Sendable {
    var name: String { get }
    var kindRaw: String { get }
    func generate(_ context: ProviderGenerateContext) async throws -> String
}

@available(macOS 26, *)
public typealias GenerationProviderType = GenerationProvider

// MARK: - Shared response guard (never paste empty / refusal)

/// Pure string gate used by every provider + GenerationService before paste.
enum ProviderResponseGuard {
    static let refusalMarkers: [String] = [
        "i can't help",
        "i cannot help",
        "i'm not able",
        "i am not able",
        "as an ai",
        "against my guidelines",
        "i won't generate",
        "i will not generate",
    ]

    static func looksLikeRefusal(_ text: String) -> Bool {
        let lower = text.lowercased()
        return refusalMarkers.contains { lower.contains($0) }
    }

    /// Check if text contains any banned guard words.
    static func containsGuardWord(_ text: String, guardWords: [String]) -> Bool {
        let lower = text.lowercased()
        return guardWords.contains { lower.contains($0.lowercased()) }
    }

    /// True only for non-empty, non-refusal text.
    static func isPasteable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !looksLikeRefusal(trimmed)
    }

    /// Trims, rejects empty + refusal-shaped strings.
    static func validatedPasteable(_ text: String, provider: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GenerationError.unsafeCandidate(reason: "empty \(provider) response")
        }
        if looksLikeRefusal(trimmed) {
            throw GenerationError.refused(reason: trimmed)
        }
        return trimmed
    }

    /// Validates against guard words. Throws guardrailViolation if banned word found.
    static func validatedAgainstGuardWords(_ text: String, guardWords: [String], provider: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if containsGuardWord(trimmed, guardWords: guardWords) {
            throw GenerationError.guardrailViolation(reason: "Output contains banned word/phrase")
        }
        return trimmed
    }

    /// Rejects run-on / too-short output. The on-device model occasionally emits
    /// a comma-joined superstring when it fixates on example fragments; this is
    /// the hard backstop so one of those can never reach the clipboard. A signoff
    /// is 2–14 words; outside that, the provider retries with a fresh attempt.
    static func validatedLength(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split { $0.isWhitespace || $0 == "," }.filter { !$0.isEmpty }
        guard words.count >= 2 else {
            throw GenerationError.guardrailViolation(reason: "Output too short")
        }
        guard words.count <= 12 else {
            throw GenerationError.guardrailViolation(reason: "Output too long (run-on)")
        }
        return trimmed
    }

    /// Strips trailing period/exclamation that the model sometimes appends after
    /// the required trailing comma (e.g. "Brain freeze, activated,." → "Brain freeze, activated,"),
    /// then guarantees exactly one trailing comma.
    static func sanitizeSignoff(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Collapse ",." ", !" ", ?" (with or without space) → ","
        while cleaned.hasSuffix(",.") || cleaned.hasSuffix(", .") || cleaned.hasSuffix(",!") || cleaned.hasSuffix(", !") || cleaned.hasSuffix(",?") || cleaned.hasSuffix(", ?") {
            // Find the comma and keep everything up to and including it
            if let commaIdx = cleaned.lastIndex(of: ",") {
                cleaned = String(cleaned[...commaIdx])
            } else {
                cleaned.removeLast()
            }
        }
        // Strip any remaining trailing period / exclamation / question mark.
        while let last = cleaned.last, last == "." || last == "!" || last == "?" {
            cleaned.removeLast()
        }
        // Trim again after stripping punctuation.
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip trailing "comma" word if model wrote it out (e.g. "phrase comma" → "phrase,")
        let lower = cleaned.lowercased()
        if lower.hasSuffix(" comma") || lower.hasSuffix(" comma,") || lower.hasSuffix(" comma.") {
            // Remove " comma" or " comma," or " comma." and ensure trailing comma
            // " comma" = 6 chars, " comma," = 7 chars, " comma." = 7 chars
            if lower.hasSuffix(" comma,") {
                cleaned.removeLast(7)
            } else if lower.hasSuffix(" comma.") {
                cleaned.removeLast(7)
            } else {
                cleaned.removeLast(6)
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.hasSuffix(",") {
                cleaned.append(",")
            }
        }
        // Collapse trailing double commas.
        while cleaned.hasSuffix(",,") {
            cleaned.removeLast()
        }
        // Ensure exactly one trailing comma.
        if !cleaned.hasSuffix(",") {
            cleaned.append(",")
        }
        return cleaned
    }

    @available(macOS 26, *)
    static func temperature(for context: ProviderGenerateContext) -> Double {
        if let level = context.unhingedLevel {
            switch level {
            case .calm: return 0.4
            case .regular: return 0.5
            case .deranged: return 0.6
            case .cynical: return 0.5
            }
        } else if let tone = context.toneValue {
            return 0.4 + (tone * 0.2)  // Lower base for professional (0.4-0.6)
        }
        // Standard bucket: higher temperature for more creative/varied output
        return 0.7
    }
}

// MARK: - Foundation Models

@available(macOS 26, *)
public struct FoundationModelsProvider: GenerationProvider {
    public let name = "Apple Foundation Models"
    public let kindRaw = GenerationProviderKind.foundationModels.rawValue

    public init() {}

    public func generate(_ context: ProviderGenerateContext) async throws -> String {
#if canImport(FoundationModels)
        let availability = FoundationModelsAvailability.probe()
        guard case .available = availability else {
            throw GenerationError.unavailable(
                reason: FoundationModelsAvailability.userFacingCause(for: availability)
            )
        }

        // Retry up to 3 times on guard word violations
        var lastError: (any Error)?
        for attempt in 1...3 {
            let output: SignoffOutput
            do {
                output = try await FoundationModelsSessionPool.shared.respond(
                    bucketId: context.bucketId,
                    instructions: context.composed.instructions,
                    prompt: context.composed.prompt,
                    options: Self.generationOptions(for: context)
                )
            } catch {
                throw error
            }
            let sanitized = ProviderResponseGuard.sanitizeSignoff(output.text)
            let pasteable = try ProviderResponseGuard.validatedPasteable(sanitized, provider: "FMF")
            let lengthValidated = try ProviderResponseGuard.validatedLength(pasteable)

            // Check against guard words
            do {
                let guardValidated = try ProviderResponseGuard.validatedAgainstGuardWords(lengthValidated, guardWords: context.guardWords, provider: "FMF")
                return guardValidated
            } catch let err as GenerationError {
                if case .guardrailViolation = err {
                    lastError = err
                    if attempt < 3 {
                        continue
                    }
                } else {
                    throw err
                }
            }
        }

        // If we exhausted retries on guardrail, throw the last error
        if let lastError {
            throw lastError
        }

        // Fallback - should not reach here
        throw GenerationError.guardrailViolation(reason: "Output contains banned word/phrase after retries")
#else
        throw GenerationError.unavailable(
            reason: "FoundationModels module not available in this SDK"
        )
#endif
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
extension FoundationModelsProvider {
    fileprivate static func generationOptions(for context: ProviderGenerateContext) -> GenerationOptions {
        GenerationOptions(
            temperature: ProviderResponseGuard.temperature(for: context),
            maximumResponseTokens: 128
        )
    }
}
#endif

// MARK: - Errors

public enum GenerationError: Error, Equatable, Sendable {
    case unavailable(reason: String)
    case timeout
    case unsafeCandidate(reason: String)
    case quotaBlocked(reason: String)
    case refused(reason: String)
    case guardrailViolation(reason: String)
    case contextWindowExceeded
    case providerFailed(reason: String)
}

/// Quiet, non-blocking notice when Foundation Models miss and bundled serves
/// instead. Surfaces on the popover status line — never blocks paste,
/// never replaces the signature preview.
public enum GenerationStatusNotice: Equatable, Sendable {
    /// Internal reason tracked during the provider walk before `used` is known.
    public enum Reason: Equatable, Sendable {
        case timedOut
        case unavailable
        case fellThrough
    }

    /// 450ms hard cap lost the race; next provider won.
    case foundationModelsTimedOut(used: GenerationProviderKind)
    /// FMF reported unavailable / ineligible; bundled served instead.
    case foundationModelsUnavailable(used: GenerationProviderKind)
    /// FMF threw (or returned non-pasteable) while reported available.
    case foundationModelsFellThrough(used: GenerationProviderKind)

    public init(reason: Reason, used: GenerationProviderKind) {
        switch reason {
        case .timedOut: self = .foundationModelsTimedOut(used: used)
        case .unavailable: self = .foundationModelsUnavailable(used: used)
        case .fellThrough: self = .foundationModelsFellThrough(used: used)
        }
    }

    /// Quiet secondary status — provider label only, never alarmist.
    public var message: String {
        switch self {
        case .foundationModelsTimedOut(let used),
             .foundationModelsUnavailable(let used),
             .foundationModelsFellThrough(let used):
            return "Used \(used.badgeTitle)"
        }
    }
}
