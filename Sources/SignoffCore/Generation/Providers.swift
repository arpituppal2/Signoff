import Foundation
import RegexBuilder
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
    /// 1-based retry attempt within the caller's loop, when known. Lets the
    /// temperature ramp up on later attempts so a fixated on-device model can
    /// physically break a "toaster mood" instead of re-sampling the same
    /// attractor at a fixed low temperature.
    public let attempt: Int?

    public init(bucketId: String,
                template: PromptTemplate,
                composed: PromptComposer.Composed,
                unhingedLevel: UnhingedLevel? = nil,
                toneValue: Double? = nil,
                attempt: Int? = nil) {
        self.bucketId = bucketId
        self.template = template
        self.composed = composed
        self.unhingedLevel = unhingedLevel
        self.toneValue = toneValue
        self.attempt = attempt
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
/// Optimized with pre-compiled NSRegularExpression for multi-pattern matching.
/// NSRegularExpression is thread-safe for read-only matching operations.
/// Public so harness/bench executables apply the same format gate as shipping.
public enum ProviderResponseGuard {
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

    /// Pre-compiled regex for refusal markers (case-insensitive).
    private static let _refusalRegex: NSRegularExpression = {
        let pattern = refusalMarkers.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }()
    static let refusalRegex: NSRegularExpression = _refusalRegex

    /// Professional bucket additional banned words.
    private static let _professionalBannedRegex: NSRegularExpression = {
        let pattern = ["lol", "haha", "lmao", "omg", "wtf", "bruh", "dude", "bro",
                      "cowabunga", "smell ya", "allegedly", "yolo", "fam",
                      "squad", "goals", "mood", "vibes", "slay", "stan"]
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        return try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }()
    static let professionalBannedRegex: NSRegularExpression = _professionalBannedRegex

    /// Cynical bucket unsafe patterns.
    private static let _unsafePatternsRegex: NSRegularExpression = {
        let pattern = ["kill yourself", "kys", "die", "suicide", "harm yourself",
                        "hate you", "fuck you", "go die", "nobody likes",
                        "worthless", "pathetic", "garbage human"]
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        return try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }()
    static let unsafePatternsRegex: NSRegularExpression = _unsafePatternsRegex

    static func looksLikeRefusal(_ text: String) -> Bool {
        refusalRegex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) != nil
    }

    /// True only for non-empty, non-refusal text.
    static func isPasteable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !looksLikeRefusal(trimmed)
    }

    /// Trims, rejects empty + refusal-shaped strings.
    public static func validatedPasteable(_ text: String, provider: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GenerationError.unsafeCandidate(reason: "empty \(provider) response")
        }
        if looksLikeRefusal(trimmed) {
            throw GenerationError.refused(reason: trimmed)
        }
        let lowercased = trimmed.lowercased()
        let leakedFormattingTerms = ["comma", "period", "exclamation mark", "question mark", "output only", "as an ai"]
        if leakedFormattingTerms.contains(where: { lowercased.contains($0) }) {
            throw GenerationError.unsafeCandidate(reason: "formatting instruction leaked into output")
        }
        return trimmed
    }

    static func validatedProfessional(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if professionalBannedRegex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)) != nil {
            throw GenerationError.guardrailViolation(reason: "Professional bucket contains inappropriate term")
        }
        return trimmed
    }

    static func validatedCynical(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if unsafePatternsRegex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)) != nil {
            throw GenerationError.guardrailViolation(reason: "Cynical bucket contains unsafe content")
        }
        return trimmed
    }

    /// Rejects run-on / too-short output. The on-device model occasionally emits
    /// a comma-joined superstring when it fixates on example fragments; this is
    /// the hard backstop so one of those can never reach the clipboard. Tight
    /// per-bucket caps (professional ≤3, standard ≤7, unhinged ≤8) are enforced
    /// here as an absolute ceiling; SignoffQualityValidator applies the same
    /// limits as the soft check.
    static func validatedLength(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split { $0.isWhitespace || $0 == "," }.filter { !$0.isEmpty }
        guard words.count >= 1 else {
            throw GenerationError.guardrailViolation(reason: "Output too short")
        }
        guard words.count <= 8 else {
            throw GenerationError.guardrailViolation(reason: "Output too long (run-on)")
        }
        return trimmed
    }

    /// Normalizes the product format after semantic generation.
    /// first word capitalized. Deliberately MINIMAL — the mid-line truncation
    /// surgery and punctuation fixup loops were 3B-era compensation; run-ons
    /// and over-length lines are rejected by `validatedLength` instead (a
    /// rejected candidate simply re-rolls), and cloud models emit clean format.
    public static func sanitizeSignoff(_ text: String, bucketId: String? = nil) -> String {
        // 1. First non-empty line only — kills multi-line runaways.
        var cleaned = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
        // 2. Strip wrapping quotes/dashes/markdown bullets.
        cleaned = cleaned
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"-'•*#[]`"))
            .trimmingCharacters(in: .whitespaces)
        // 3. Collapse doubled commas, strip trailing sentence punctuation.
        while cleaned.contains(",,") {
            cleaned = cleaned.replacingOccurrences(of: ",,", with: ",")
        }
        while let last = cleaned.last, ".!?".contains(last) {
            cleaned.removeLast()
            cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        }
        while cleaned.hasSuffix(",") {
            cleaned.removeLast()
            cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        }
        // 4. Exactly one trailing comma + capitalized first word.
        if !cleaned.isEmpty {
            cleaned.append(",")
        }
        if let first = cleaned.first, first.isLetter {
            cleaned = String(first).uppercased() + cleaned.dropFirst()
        }
        return cleaned
    }

    @available(macOS 26, *)
    static func temperature(for context: ProviderGenerateContext) -> Double {
        // Explicit per-bucket temperature (avoids dynamic toneValue fallthrough).
        // Switches on the actual BucketID rawValue (see Models/Bucket.swift).
        // standard (Normal): 0.65 — constrained enough to avoid the
        //   noun-collision/opener-fixation ruts the on-device 3B model drifts
        //   into under high entropy (the same drift documented for unhinged
        //   below), while still creative enough to vary shapes. 0.8 left the
        //   model ruting hard on the fake-origin verb-prep scaffold.
        // professional: 0.3       — constrained, consistent
        // unhinged (Cynical): 0.6 — edgy but controlled. Lower than standard on
        //   purpose: the on-device 3B model drifts into noun-collision ruts and
        //   opener-fixation under high entropy, and the unhinged prompt + 13
        //   validator rules exist precisely to catch that drift. Running at 0.8
        //   (the prior default, reached only because the case below read
        //   "cynical" — which matched no bucket — so every unhinged generation
        //   fell through to `default`) left the model at maximum entropy, which
        //   raised per-attempt rejection pressure and made 12-attempt
        //   exhaustion (the documented failure mode) more likely. 0.6 keeps the
        //   model closer to the register few-shot examples; register-cycling +
        //   the validator's dedup/rut fingerprints handle diversity.
        switch context.bucketId {
        case "professional": return GenerationTuning.temperatureProfessional  // 0.3 converges onto closers already in dedup; 0.7 glued closers. 0.55 spreads mass without glue.
        case "unhinged": return Self.rampedUnhingedTemperature(attempt: context.attempt)
        case "standard": return GenerationTuning.temperatureStandard
        default: return GenerationTuning.temperatureDefault
        }
    }

    /// Unhinged temperature with a per-attempt ramp. Attempt 1 stays at the
    /// grounded base (0.68) so the first roll hugs the register few-shots and
    /// is most likely to be a clean, on-taste line. Each rejected attempt then
    /// raises the temperature ~0.02 up to a 0.82 ceiling — enough to widen the
    /// sample and escape a "toaster mood" / "All X, no Y" attractor, but low
    /// enough that the model still honors the "subvert something recognizable"
    /// instruction. A higher ceiling (0.95, tried) breaks the lock but the
    /// model ignores the prompt and emits random poetic salad ("soggy sock
    /// drawer where silence screams"), which is worse than an honest failure.
    /// A nil attempt (e.g. generateRaw single-roll) uses the base unchanged.
    @available(macOS 26, *)
    static func rampedUnhingedTemperature(attempt: Int?) -> Double {
        guard let attempt, attempt > 1 else { return GenerationTuning.temperatureUnhinged }
        let base = GenerationTuning.temperatureUnhinged
        let ramp = min(Double(attempt - 1) * 0.02, 0.14)
        return min(base + ramp, 0.82)
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

        // Single roll — this is now the OFFLINE FALLBACK path; the caller
        // owns retries. Safety/format gates are per-bucket below.
        let output: SignoffOutput = try await FoundationModelsSessionPool.shared.respond(
            bucketId: context.bucketId,
            instructions: context.composed.instructions,
            prompt: context.composed.prompt,
            options: Self.generationOptions(for: context)
        )
        let sanitized = ProviderResponseGuard.sanitizeSignoff(output.text, bucketId: context.bucketId)
        let pasteable = try ProviderResponseGuard.validatedPasteable(sanitized, provider: "FMF")
        let lengthValidated = try ProviderResponseGuard.validatedLength(pasteable)
        switch context.bucketId {
        case "professional":
            return try ProviderResponseGuard.validatedProfessional(lengthValidated)
        case "unhinged":
            return try ProviderResponseGuard.validatedCynical(lengthValidated)
        default:
            return lengthValidated
        }
#else
        throw GenerationError.unavailable(
            reason: "FoundationModels module not available in this SDK"
        )
#endif
    }
}

@available(macOS 26, *)
extension FoundationModelsProvider {
    fileprivate static func generationOptions(for context: ProviderGenerateContext) -> GenerationOptions {
        // 96 tokens ≈ 15-20 words — allows full phrases + breathing room for
        // @Guide comma enforcement. The per-bucket soft caps (pro ≤3, normal ≤5,
        // cynical ≤7) live in SignoffQualityValidator; this token ceiling is
        // the hard backstop so the model can't ramble.
        GenerationOptions(
            temperature: ProviderResponseGuard.temperature(for: context),
            maximumResponseTokens: 96
        )
    }
}

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
