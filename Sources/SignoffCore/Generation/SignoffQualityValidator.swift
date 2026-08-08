import Foundation

/// Curated corpus entry with mechanism categorization
public struct CuratedSignoff: Codable, Sendable, Equatable {
    public let text: String
    public let mechanism: String
    public let tags: [String]

    public init(text: String, mechanism: String, tags: [String]) {
        self.text = text
        self.mechanism = mechanism
        self.tags = tags
    }
}

/// Loaded corpus per bucket
public struct SignoffCorpus: Sendable {
    public let normal: [CuratedSignoff]
    public let cynical: [CuratedSignoff]
    public let professional: [CuratedSignoff]

    public init(normal: [CuratedSignoff], cynical: [CuratedSignoff], professional: [CuratedSignoff]) {
        self.normal = normal
        self.cynical = cynical
        self.professional = professional
    }

    public func entries(for bucketId: String) -> [CuratedSignoff] {
        switch bucketId {
        case "standard": return normal
        case "unhinged": return cynical
        case "professional": return professional
        default: return normal
        }
    }
}

/// Local quality validator for generated signoffs
@MainActor
public final class SignoffQualityValidator: ObservableObject {
    public static let shared = SignoffQualityValidator()

    // Banned words/patterns that indicate low quality
    private let bannedTokens: Set<String> = [
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

    // Banned n-gram patterns (2-3 word sequences that indicate template reuse)
    private let bannedNGrams: Set<String> = [
        "felt natural", "aligned effortlessly", "valued input shaped",
        "collaboration felt", "steady rhythm", "steady groove",
        "ghost inbox", "phantom priorities", "stale optimism",
        "inbox fumes", "running on", "feeding on"
    ]

    // Minimum/maximum word counts per bucket (spec §voice buckets)
    private let wordCountLimits: [String: ClosedRange<Int>] = [
        "standard": 2...16,
        "unhinged": 2...16,
        "professional": 1...7
    ]

    // Maximum similarity threshold (0.0 - 1.0)
    private let maxSimilarityThreshold: Double = 0.7

    private init() {}

    /// Validate a candidate signoff against quality criteria
    public func validate(_ candidate: String, forBucket bucketId: String, recentHistory: [String] = []) -> ValidationResult {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        // 1. Empty check
        if trimmed.isEmpty {
            return .invalid(reason: "Empty signoff")
        }

        // 2. Word count check
        let words = trimmed.split { $0.isWhitespace || $0 == "," || $0 == "." }.filter { !$0.isEmpty }
        let wordCount = words.count
        if let range = wordCountLimits[bucketId] {
            if wordCount < range.lowerBound || wordCount > range.upperBound {
                return .invalid(reason: "Word count \(wordCount) outside range \(range) for \(bucketId)")
            }
        }

        // 3. Multi-line check (should be single line for most buckets)
        if trimmed.contains("\n") && bucketId != "footer" {
            return .invalid(reason: "Multi-line output not allowed")
        }

        // 4. Model narration check
        let narrationPatterns = [
            "signoff:", "here's one:", "here is one:",
            "here's a signoff:", "here is a signoff:",
            "output:", "result:", "generated:",
            "i would say:", "i'd say:", "you could use:"
        ]
        for pattern in narrationPatterns {
            if lowercased.hasPrefix(pattern) || lowercased.contains(" \(pattern)") {
                return .invalid(reason: "Contains model narration: \(pattern)")
            }
        }

        // 5. Quotes/markdown check
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") {
            return .invalid(reason: "Wrapped in quotes")
        }
        if trimmed.hasPrefix("'") && trimmed.hasSuffix("'") {
            return .invalid(reason: "Wrapped in single quotes")
        }
        if trimmed.contains("**") || trimmed.contains("*") || trimmed.contains("#") || trimmed.contains("`") {
            return .invalid(reason: "Contains markdown formatting")
        }

        // 6. Banned tokens check
        for token in bannedTokens {
            if lowercased.contains(token.lowercased()) {
                return .invalid(reason: "Contains banned token: \(token)")
            }
        }

        // 7. Banned n-grams check
        for ngram in bannedNGrams {
            if lowercased.contains(ngram.lowercased()) {
                return .invalid(reason: "Contains banned n-gram: \(ngram)")
            }
        }

        // 8. Exact duplicate check against recent history
        let normalizedCandidate = normalizeForComparison(trimmed)
        for recent in recentHistory {
            let normalizedRecent = normalizeForComparison(recent)
            if normalizedCandidate == normalizedRecent {
                return .invalid(reason: "Exact duplicate of recent signoff")
            }
        }

        // 9. High similarity check against recent history
        for recent in recentHistory {
            let similarity = jaccardSimilarity(normalizedCandidate, normalizeForComparison(recent))
            if similarity > maxSimilarityThreshold {
                return .invalid(reason: "Too similar to recent signoff (similarity: \(String(format: "%.2f", similarity)))")
            }
        }

        // 10. Mechanism diversity check (don't repeat same mechanism too often)
        // This is a soft check - we just track it

        // 11. Bucket-specific checks
        if bucketId == "professional" {
            // Professional must not have jokes, twists, or casual language
            let professionalBanned = ["lol", "haha", "lmao", "omg", "wtf", "bruh", "dude", "bro",
                                     "cowabunga", "smell ya", "allegedly", "yolo", "fam",
                                     "squad", "goals", "mood", "vibes", "slay", "stan"]
            for banned in professionalBanned {
                if lowercased.contains(banned) {
                    return .invalid(reason: "Professional bucket contains inappropriate term: \(banned)")
                }
            }
        }

        if bucketId == "unhinged" {
            // Cynical must not be genuinely hostile or unsafe
            let unsafePatterns = ["kill yourself", "kys", "die", "suicide", "harm yourself",
                                 "hate you", "fuck you", "go die", "nobody likes",
                                 "worthless", "pathetic", "garbage human"]
            for unsafe in unsafePatterns {
                if lowercased.contains(unsafe) {
                    return .invalid(reason: "Cynical bucket contains unsafe content: \(unsafe)")
                }
            }
        }

        // 12. Readability check - must have at least one vowel per word on average
        let vowelCount = lowercased.filter { "aeiou".contains($0) }.count
        if wordCount > 0 && vowelCount < wordCount {
            return .invalid(reason: "Poor readability (insufficient vowels)")
        }

        return .valid(trimmed)
    }

    /// Select a fresh curated entry, avoiding recent history
    public func selectCuratedFallback(forBucket bucketId: String, recentHistory: [String] = [], usedMechanisms: [String] = []) -> CuratedSignoff? {
        let corpus = SignoffCorpusLoader.shared.corpus
        let entries = corpus.entries(for: bucketId)
        let normalizedHistory = Set(recentHistory.map { normalizeForComparison($0) })

        // First pass: find completely unused entries with diverse mechanisms
        var candidates = entries.filter { entry in
            !normalizedHistory.contains(normalizeForComparison(entry.text)) &&
            !usedMechanisms.contains(entry.mechanism)
        }

        if !candidates.isEmpty {
            return candidates.randomElement()
        }

        // Second pass: find unused entries, any mechanism
        candidates = entries.filter { entry in
            !normalizedHistory.contains(normalizeForComparison(entry.text))
        }

        if !candidates.isEmpty {
            return candidates.randomElement()
        }

        // Third pass: least recently used with mechanism diversity
        // For simplicity, just return random from all
        return entries.randomElement()
    }

    // MARK: - Internal Helpers

    private func normalizeForComparison(_ text: String) -> String {
        return text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func jaccardSimilarity(_ a: String, _ b: String) -> Double {
        let setA = Set(a.components(separatedBy: " "))
        let setB = Set(b.components(separatedBy: " "))
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }
}

public enum ValidationResult: Equatable, Sendable {
    case valid(String)
    case invalid(reason: String)

    public var isValid: Bool {
        switch self {
        case .valid: return true
        case .invalid: return false
        }
    }

    public var value: String? {
        switch self {
        case .valid(let s): return s
        case .invalid: return nil
        }
    }
}

/// Corpus loader - loads JSON files at startup
@MainActor
public final class SignoffCorpusLoader: ObservableObject {
    public static let shared = SignoffCorpusLoader()

    @Published public private(set) var corpus: SignoffCorpus = SignoffCorpus(normal: [], cynical: [], professional: [])
    @Published public private(set) var isLoaded = false

    private init() {}

    public func load() {
        // Only load once
        guard !isLoaded else { return }

        let bundle = Bundle.module
        var normal: [CuratedSignoff] = []
        var cynical: [CuratedSignoff] = []
        var professional: [CuratedSignoff] = []

        // Load normal
        if let url = bundle.url(forResource: "normal", withExtension: "json", subdirectory: "Corpus"),
           let data = try? Data(contentsOf: url),
           let wrapper = try? JSONDecoder().decode(CorpusWrapper.self, from: data) {
            normal = wrapper.signoffs
        }

        // Load cynical
        if let url = bundle.url(forResource: "cynical", withExtension: "json", subdirectory: "Corpus"),
           let data = try? Data(contentsOf: url),
           let wrapper = try? JSONDecoder().decode(CorpusWrapper.self, from: data) {
            cynical = wrapper.signoffs
        }

        // Load professional
        if let url = bundle.url(forResource: "professional", withExtension: "json", subdirectory: "Corpus"),
           let data = try? Data(contentsOf: url),
           let wrapper = try? JSONDecoder().decode(CorpusWrapper.self, from: data) {
            professional = wrapper.signoffs
        }

        corpus = SignoffCorpus(normal: normal, cynical: cynical, professional: professional)
        isLoaded = true

        // Verify minimum corpus sizes
        SignoffLogLogger(.generation).info("Corpus loaded: normal=\(normal.count), cynical=\(cynical.count), professional=\(professional.count)")
    }
}

private struct CorpusWrapper: Codable {
    let signoffs: [CuratedSignoff]
}