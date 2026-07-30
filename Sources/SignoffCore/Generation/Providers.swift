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

    public init(bucketId: String,
                template: PromptTemplate,
                composed: PromptComposer.Composed,
                unhingedLevel: UnhingedLevel? = nil,
                toneValue: Double? = nil) {
        self.bucketId = bucketId
        self.template = template
        self.composed = composed
        self.unhingedLevel = unhingedLevel
        self.toneValue = toneValue
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

    @available(macOS 26, *)
    static func temperature(for context: ProviderGenerateContext) -> Double {
        if let level = context.unhingedLevel {
            switch level {
            case .calm: return 0.65
            case .regular: return 0.85
            case .deranged: return 1.0
            case .cynical: return 0.75
            }
        } else if let tone = context.toneValue {
            return 0.45 + (tone * 0.4)
        }
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

        let output = try await FoundationModelsSessionPool.shared.respond(
            bucketId: context.bucketId,
            instructions: context.composed.instructions,
            prompt: context.composed.prompt,
            options: Self.generationOptions(for: context)
        )
        return try ProviderResponseGuard.validatedPasteable(output.text, provider: "FMF")
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
            maximumResponseTokens: 64
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
