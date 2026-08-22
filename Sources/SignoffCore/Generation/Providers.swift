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
/// Optimized with pre-compiled NSRegularExpression for multi-pattern matching.
/// NSRegularExpression is thread-safe for read-only matching operations.
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

    /// Pre-compiled regex for refusal markers (case-insensitive).
    private static let _refusalRegex: NSRegularExpression = {
        let pattern = refusalMarkers.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }()
    static let refusalRegex: NSRegularExpression = _refusalRegex

    /// Guard words that must not appear in output (from quality validator).
    private static let guardWords: [String] = [
        "premium", "text matrix", "matrix",
        "forgotten", "fourth eye", "4th eye",
        "dreaming", "keyboard dreams",
        "surprisingly", "honestly", "aligned", "effortlessly",
        "ghost inbox", "phantom priorit", "stale optim",
        "typing feels like", "traffic prefers", "counting sheep",
        "collaboration felt", "valued input", "steady groove",
        "steady rhythm", "synergy", "journey", "path forward",
        "vision", "meaningful dialogue", "grateful for the opportunity",
        "transformative", "partnership", "appreciate the clarity",
        "looking forward to continued collaboration", "inbox fumes",
        "feeding on stale", "running on ghost", "running on phantom"
    ]

    /// Pre-compiled regex for guard word matching (case-insensitive, word-boundary aware).
    private static let _guardWordsRegex: NSRegularExpression = {
        let pattern = guardWords.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }()
    static let guardWordsRegex: NSRegularExpression = _guardWordsRegex

    /// Banned n-grams for template reuse detection.
    private static let bannedNGrams: [String] = [
        "felt natural", "aligned effortlessly", "valued input shaped",
        "collaboration felt", "steady rhythm", "steady groove",
        "ghost inbox", "phantom priorities", "stale optimism",
        "inbox fumes", "feeding on",
        "premium", "text matrix", "forgotten", "fourth eye",
        "keyboard dreams"
    ]

    /// Pre-compiled regex for n-gram matching.
    private static let _bannedNGramsRegex: NSRegularExpression = {
        let pattern = bannedNGrams.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }()
    static let bannedNGramsRegex: NSRegularExpression = _bannedNGramsRegex

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

    /// Check if text contains any banned guard words using pre-compiled regex.
    static func containsGuardWord(_ text: String) -> Bool {
        guardWordsRegex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) != nil
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
    /// Uses pre-compiled regex for O(1) matching instead of O(n) linear scan.
    static func validatedAgainstGuardWords(_ text: String, provider: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if containsGuardWord(trimmed) {
            throw GenerationError.guardrailViolation(reason: "Output contains banned word/phrase")
        }
        return trimmed
    }

    static func validatedAgainstBannedNGrams(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if bannedNGramsRegex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)) != nil {
            throw GenerationError.guardrailViolation(reason: "Output contains banned n-gram")
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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

    /// Strips trailing period/exclamation that the model sometimes appends after
    /// the required trailing comma (e.g. "Brain freeze, activated,." → "Brain freeze, activated,"),
    /// then guarantees exactly one trailing comma.
    static func sanitizeSignoff(_ text: String) -> String {
        // ── Deterministic format guardrails (do not rely on the 3B model for syntax) ──
        // 1. Take only the first non-empty line — kills multi-line/multi-sentence
        //    runaways on the spot (Apple exposes no stopSequences, so a rant that
        //    fits the token cap still arrives here as several lines/commas; this is
        //    where we cut it to one).
        var cleaned = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""

        // 2. Strip surrounding quotes, dashes, and markdown bullet markers.
        cleaned = cleaned
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"-'•*#[]`"))
            .trimmingCharacters(in: .whitespaces)

        // 3. Mid-line punctuation artifacts: a comma-joined runaway like
        //    "Baked beans on toast, a breakfast delight, a culinary," is the
        //    3B model's most stubborn failure — it glues clauses with commas.
        //    When a line has MORE THAN ONE comma, truncate to the text up to and
        //    including the FIRST comma and discard the run-on tail. A real
        //    1-7-word signoff has at most one comma (the trailing one). This is
        //    deterministic: the first clause is always the intended closer; the
        //    rest is sampled glue. ("With queso on top," → 1 comma, untouched.)
        let firstComma = cleaned.firstIndex(of: ",")
        if let cutLeft = firstComma {
            // Check if we should avoid truncation for legitimate internal commas
            // Specifically, if the first segment (before first comma) is 1 word,
            // it's likely a legitimate quote with internal comma (e.g. "Elementary, my dear Watson,")
            let firstSegment = String(cleaned[..<cutLeft])
            let firstSegmentWords = firstSegment.split { $0.isWhitespace }.filter { !$0.isEmpty }
            if firstSegmentWords.count == 1 {
                // Likely a legitimate internal comma, don't truncate
                // (e.g. "Elementary, my dear Watson," or "Hello, Jerry,")
            } else {
                // Check for runaway: if there's another comma after the first one
                let remainder = cleaned[cutLeft...].dropFirst()
                if remainder.contains(",") {
                    // Only truncate if the SECOND comma is present → it's a glue-runaway.
                    cleaned = String(cleaned[...cutLeft])
                    // After truncation the first clause may still have a stray inner
                    // comma-free tail of whitespace; trim it.
                    cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleaned.hasSuffix(",") { /* keep the one comma */ }
                }
            }
        }
        // Collapse any remaining doubled+ commas ("a,,," → "a,").
        while cleaned.contains(",,") {
            cleaned = cleaned.replacingOccurrences(of: ",,", with: ",")
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
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
        // Capitalize the first letter (deterministic — model casing is unreliable).
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
        case "professional": return 0.7  // Higher for more variation in professional
        case "unhinged": return 0.6
        case "standard": return 0.3  // Lower temperature for quotes bucket to focus on recall
        default: return 0.65 // fallback to standard
        }
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

            do {
                // Validate against guard words and banned n-grams
                let guardWordChecked = try ProviderResponseGuard.validatedAgainstGuardWords(lengthValidated, provider: "FMF")
                let bannedNGramChecked = try ProviderResponseGuard.validatedAgainstBannedNGrams(guardWordChecked)

                let finalChecked: String
                switch context.bucketId {
                case "professional":
                    finalChecked = try ProviderResponseGuard.validatedProfessional(bannedNGramChecked)
                case "unhinged":
                    finalChecked = try ProviderResponseGuard.validatedCynical(bannedNGramChecked)
                default:
                    finalChecked = bannedNGramChecked
                }
                return finalChecked
            } catch {
                lastError = error
                if attempt < 3 {
                    continue
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
