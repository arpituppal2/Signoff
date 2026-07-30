import Foundation
import SwiftData

/// VoiceProfile — the silent intelligence engine that learns the user's communication
/// style from ALL observed writing across apps. It distinguishes between quality
/// patterns (what the user keeps/sends) vs noise patterns (what they delete/abandon).
/// Built locally, encrypted at rest, never synced. This is what makes Signoff unique.
@Model
public final class VoiceProfile: @unchecked Sendable {
    @Attribute(.unique) public var id: String = "primary"

    // MARK: - Quality Fingerprints (The Core Innovation)

    /// N-gram frequencies from ACCEPTED writing (sent emails, saved docs, sent messages)
    /// These are the patterns the user explicitly chose to keep
    public var qualityLexicalFingerprintData: Data = Data()

    /// N-gram frequencies from REJECTED writing (deleted drafts, abandoned compositions)
    /// These are patterns the user actively avoided - anti-patterns for generation
    public var noiseLexicalFingerprintData: Data = Data()

    // MARK: - Rhythm & Structure (Quality Only)

    public var qualityAvgSentenceLength: Double = 0
    public var qualityPunctuationStyleData: Data = Data()
    public var qualityFormalityScore: Double = 0.5
    public var qualityEmojiFrequency: Double = 0
    public var qualityVocabularyRichness: Double = 0

    // MARK: - Observed Patterns

    /// Signoffs the user actually sent/used (extracted from sent messages)
    public var adoptedSignoffPatternsData: Data = Data()

    /// Signoffs the user typed but deleted/replaced (anti-patterns)
    public var rejectedSignoffPatternsData: Data = Data()

    /// Writing contexts observed (app -> quality score)
    public var contextQualityWeightsData: Data = Data()

    // MARK: - Metadata

    public var lastUpdated: Date = Date()
    public var version: Int = 2
    public var totalQualityObservations: Int = 0
    public var totalNoiseObservations: Int = 0
    public var isLearningPaused: Bool = false
    public var learningConsentGranted: Bool = false
    public var observedAppsData: Data = Data()

    public init() {}
}

@MainActor
public extension VoiceProfile {
    /// Singleton access - loads from persistence if available
    static let shared: VoiceProfile = {
        let vp = VoiceProfile()
        return vp
    }()

    /// Initialize the shared instance after persistence is ready
    static func initialize() {
        if let existing = try? PersistenceController.shared.fetchVoiceProfile() {
            let shared = VoiceProfile.shared
            shared.qualityLexicalFingerprint = existing.qualityLexicalFingerprint
            shared.noiseLexicalFingerprint = existing.noiseLexicalFingerprint
            shared.qualityAvgSentenceLength = existing.qualityAvgSentenceLength
            shared.qualityPunctuationStyle = existing.qualityPunctuationStyle
            shared.qualityFormalityScore = existing.qualityFormalityScore
            shared.qualityEmojiFrequency = existing.qualityEmojiFrequency
            shared.qualityVocabularyRichness = existing.qualityVocabularyRichness
            shared.adoptedSignoffPatterns = existing.adoptedSignoffPatterns
            shared.rejectedSignoffPatterns = existing.rejectedSignoffPatterns
            shared.contextQualityWeights = existing.contextQualityWeights
            shared.totalQualityObservations = existing.totalQualityObservations
            shared.totalNoiseObservations = existing.totalNoiseObservations
            shared.isLearningPaused = existing.isLearningPaused
            shared.learningConsentGranted = existing.learningConsentGranted
            shared.observedApps = existing.observedApps
            shared.lastUpdated = existing.lastUpdated
            shared.version = existing.version
        }
        try? PersistenceController.shared.saveVoiceProfile(shared)
    }
}

public extension VoiceProfile {
    // MARK: - Quality Fingerprints

    var qualityLexicalFingerprint: [String: Double] {
        get { decode(qualityLexicalFingerprintData) ?? [:] }
        set { qualityLexicalFingerprintData = encode(newValue) ?? Data() }
    }

    var noiseLexicalFingerprint: [String: Double] {
        get { decode(noiseLexicalFingerprintData) ?? [:] }
        set { noiseLexicalFingerprintData = encode(newValue) ?? Data() }
    }

    /// The discriminative fingerprint: quality patterns BOOSTED, noise patterns SUPPRESSED
    /// This is what gets injected into the FMF prompt - the "good taste" filter
    var discriminativeFingerprint: [String: Double] {
        var result: [String: Double] = [:]
        let quality = qualityLexicalFingerprint
        let noise = noiseLexicalFingerprint

        // Boost quality n-grams
        for (gram, weight) in quality {
            result[gram, default: 0] += weight * 1.5
        }

        // Suppress noise n-grams (negative weight = avoid this pattern)
        for (gram, weight) in noise {
            result[gram, default: 0] -= weight * 0.8
        }

        // Keep only positively weighted patterns
        return result.filter { $0.value > 0 }
    }

    // MARK: - Quality Rhythm & Structure

    var qualityPunctuationStyle: PunctuationProfile {
        get { decode(qualityPunctuationStyleData) ?? PunctuationProfile() }
        set { qualityPunctuationStyleData = encode(newValue) ?? Data() }
    }

    // MARK: - Patterns

    var adoptedSignoffPatterns: [String] {
        get { decode(adoptedSignoffPatternsData) ?? [] }
        set { adoptedSignoffPatternsData = encode(newValue) ?? Data() }
    }

    var rejectedSignoffPatterns: [String] {
        get { decode(rejectedSignoffPatternsData) ?? [] }
        set { rejectedSignoffPatternsData = encode(newValue) ?? Data() }
    }

    var contextQualityWeights: [String: Double] {
        get { decode(contextQualityWeightsData) ?? [:] }
        set { contextQualityWeightsData = encode(newValue) ?? Data() }
    }

    var observedApps: [String] {
        get { decode(observedAppsData) ?? [] }
        set { observedAppsData = encode(newValue) ?? Data() }
    }

    // MARK: - Prompt Injection (The "Secret Sauce")

    /// High-level summary for FMF system prompt - describes the user's GOOD voice
    var qualityPromptSummary: String {
        let formality = qualityFormalityScore > 0.6 ? "formal" : qualityFormalityScore > 0.35 ? "balanced" : "casual"
        let punct = qualityPunctuationStyle.dominant
        let emoji = qualityEmojiFrequency > 0.1 ? "occasionally uses emoji" : "rarely uses emoji"
        let adopted = adoptedSignoffPatterns.suffix(3).joined(separator: ", ")
        let rejected = rejectedSignoffPatterns.suffix(2).joined(separator: ", ")

        var parts: [String] = []
        parts.append("Writes in a \(formality) register naturally")
        parts.append("Average sentence: \(String(format: "%.1f", qualityAvgSentenceLength)) words")
        parts.append("Prefers '\(punct)' punctuation")
        parts.append(emoji)
        if !adopted.isEmpty {
            parts.append("Signoffs they actually use: \(adopted)")
        }
        if !rejected.isEmpty {
            parts.append("Avoid - they delete/replace: \(rejected)")
        }
        return parts.joined(separator: ". ")
    }

    /// Detailed summary including noise patterns for debugging/transparency
    var fullPromptSummary: String {
        var parts = [qualityPromptSummary]

        let noiseGrams = noiseLexicalFingerprint
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { "\"\($0.key)\" (\(String(format: "%.2f", $0.value)))" }
            .joined(separator: ", ")

        if !noiseGrams.isEmpty {
            parts.append("Patterns they avoid: \(noiseGrams)")
        }

        let qualityGrams = qualityLexicalFingerprint
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { "\"\($0.key)\" (\(String(format: "%.2f", $0.value)))" }
            .joined(separator: ", ")

        if !qualityGrams.isEmpty {
            parts.append("Patterns they favor: \(qualityGrams)")
        }

        return parts.joined(separator: "\n")
    }

    /// Compact display for Settings → Privacy → "What I've Learned"
    var displaySummary: VoiceProfileDisplay {
        VoiceProfileDisplay(
            formalityPercent: Int(qualityFormalityScore * 100),
            avgSentenceLength: qualityAvgSentenceLength,
            punctuationStyle: qualityPunctuationStyle,
            emojiPercent: Int(qualityEmojiFrequency * 100),
            adoptedClosers: Array(adoptedSignoffPatterns.suffix(5)),
            rejectedClosers: Array(rejectedSignoffPatterns.suffix(3)),
            qualityObservations: totalQualityObservations,
            noiseObservations: totalNoiseObservations,
            observedApps: observedApps,
            lastUpdated: lastUpdated
        )
    }

    // MARK: - Learning Methods (The Core Intelligence)

    /// Learn from ADOPTED (quality) writing
    func learn(from writing: ObservedWriting) {
        // Update n-gram fingerprint (quality)
        let grams = extractNGrams(from: writing.text, n: 3)
        for gram in grams {
            qualityLexicalFingerprint[gram, default: 0] += 1.0 * writing.context.qualityWeight
        }

        // Update rhythm
        let alpha = 0.1 // EMA smoothing
        qualityAvgSentenceLength = qualityAvgSentenceLength * (1 - alpha) + Double(words(in: writing.text).count) / max(1, Double(writing.metadata.sentenceCount)) * alpha

        // Update punctuation
        qualityPunctuationStyle = blendPunctuation(qualityPunctuationStyle, writing.metadata.punctuation, weight: writing.context.qualityWeight)

        // Update formality
        qualityFormalityScore = qualityFormalityScore * (1 - alpha) + computeFormalityScore(writing.metadata.formalityIndicators) * alpha

        // Update emoji frequency
        qualityEmojiFrequency = qualityEmojiFrequency * (1 - alpha) + (writing.metadata.hasEmoji ? 1.0 : 0.0) * alpha

        // Update vocabulary richness
        qualityVocabularyRichness = qualityVocabularyRichness * (1 - alpha) + computeVocabularyRichness(writing.text) * alpha

        totalQualityObservations += 1
        lastUpdated = Date()
    }

    /// Learn from REJECTED (noise) writing
    func learnNoise(from writing: ObservedWriting) {
        let grams = extractNGrams(from: writing.text, n: 3)
        for gram in grams {
            noiseLexicalFingerprint[gram, default: 0] += 1.0 * writing.context.qualityWeight
        }
        totalNoiseObservations += 1
        lastUpdated = Date()
    }

    func adoptSignoff(_ signoff: String) {
        let clean = signoff.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty {
            var patterns = adoptedSignoffPatterns
            patterns.removeAll { $0.lowercased() == clean.lowercased() }
            patterns.append(clean)
            adoptedSignoffPatterns = Array(patterns.suffix(20))
        }
    }

    func rejectSignoff(_ signoff: String) {
        let clean = signoff.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty {
            var patterns = rejectedSignoffPatterns
            patterns.removeAll { $0.lowercased() == clean.lowercased() }
            patterns.append(clean)
            rejectedSignoffPatterns = Array(patterns.suffix(10))
        }
    }

    func observeApp(_ bundleID: String) {
        var apps = observedApps
        if !apps.contains(bundleID) {
            apps.append(bundleID)
            observedApps = apps
        }
    }

    func reset() {
        qualityLexicalFingerprint = [:]
        noiseLexicalFingerprint = [:]
        qualityAvgSentenceLength = 0
        qualityPunctuationStyle = PunctuationProfile()
        qualityFormalityScore = 0.5
        qualityEmojiFrequency = 0
        qualityVocabularyRichness = 0
        adoptedSignoffPatterns = []
        rejectedSignoffPatterns = []
        contextQualityWeights = [:]
        totalQualityObservations = 0
        totalNoiseObservations = 0
        isLearningPaused = false
        learningConsentGranted = false
        observedApps = []
        lastUpdated = Date()
    }

    // MARK: - Helpers

    private func extractNGrams(from text: String, n: Int) -> [String] {
        let words = text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }

        guard words.count >= n else { return [] }

        return (0...words.count - n).map { i in
            words[i..<i+n].joined(separator: " ")
        }
    }

    private func words(in text: String) -> [String] {
        text.split { $0.isWhitespace || $0.isPunctuation }.map(String.init)
    }

    private func blendPunctuation(_ current: PunctuationProfile, _ new: PunctuationProfile, weight: Double) -> PunctuationProfile {
        var result = PunctuationProfile()
        result.periodPercent = current.periodPercent * (1 - weight) + new.periodPercent * weight
        result.exclamationPercent = current.exclamationPercent * (1 - weight) + new.exclamationPercent * weight
        result.questionPercent = current.questionPercent * (1 - weight) + new.questionPercent * weight
        return result
    }

    private func computeFormalityScore(_ indicators: FormalityIndicators) -> Double {
        var score = 0.5
        score += indicators.latinateWordRatio * 0.3
        score -= indicators.contractionRatio * 0.2
        score -= Double(indicators.hedgeWordCount) * 0.02
        score += Double(indicators.honorificCount) * 0.05
        score -= Double(indicators.passiveVoiceCount) * 0.01
        return max(0, min(1, score))
    }

    private func computeVocabularyRichness(_ text: String) -> Double {
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        let unique = Set(words)
        guard !words.isEmpty else { return 0 }
        return Double(unique.count) / Double(words.count)
    }

    private func decode<T: Decodable>(_ data: Data) -> T? {
        try? JSONDecoder().decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }
}

public struct PunctuationProfile: Codable, Sendable, Equatable {
    public var periodPercent: Double = 0
    public var exclamationPercent: Double = 0
    public var questionPercent: Double = 0

    public init() {}

    public var dominant: String {
        let maxVal = max(periodPercent, exclamationPercent, questionPercent)
        if maxVal == periodPercent { return "." }
        if maxVal == exclamationPercent { return "!" }
        return "?"
    }

    public var display: String {
        let parts: [String] = [
            ". \(Int(periodPercent))%",
            "! \(Int(exclamationPercent))%",
            "? \(Int(questionPercent))%"
        ].filter { !$0.hasPrefix("0%") }
        return parts.joined(separator: "  ")
    }
}

public struct VoiceProfileDisplay: Sendable, Equatable, Codable {
    public let formalityPercent: Int
    public let avgSentenceLength: Double
    public let punctuationStyle: PunctuationProfile
    public let emojiPercent: Int
    public let adoptedClosers: [String]
    public let rejectedClosers: [String]
    public let qualityObservations: Int
    public let noiseObservations: Int
    public let observedApps: [String]
    public let lastUpdated: Date

    public init(formalityPercent: Int, avgSentenceLength: Double, punctuationStyle: PunctuationProfile, emojiPercent: Int, adoptedClosers: [String], rejectedClosers: [String], qualityObservations: Int, noiseObservations: Int, observedApps: [String], lastUpdated: Date) {
        self.formalityPercent = formalityPercent
        self.avgSentenceLength = avgSentenceLength
        self.punctuationStyle = punctuationStyle
        self.emojiPercent = emojiPercent
        self.adoptedClosers = adoptedClosers
        self.rejectedClosers = rejectedClosers
        self.qualityObservations = qualityObservations
        self.noiseObservations = noiseObservations
        self.observedApps = observedApps
        self.lastUpdated = lastUpdated
    }
}

/// Represents a piece of observed writing with quality classification
public struct ObservedWriting: Sendable, Equatable {
    public let text: String
    public let appBundleID: String
    public let appName: String
    public let context: WritingContext
    public let quality: WritingQuality
    public let timestamp: Date
    public let metadata: WritingMetadata

    public init(text: String, appBundleID: String, appName: String, context: WritingContext, quality: WritingQuality, timestamp: Date = Date(), metadata: WritingMetadata = WritingMetadata()) {
        self.text = text
        self.appBundleID = appBundleID
        self.appName = appName
        self.context = context
        self.quality = quality
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

public enum WritingContext: String, Codable, Sendable, CaseIterable {
    case emailCompose = "email_compose"
    case emailReply = "email_reply"
    case messageSend = "message_send"
    case documentSave = "document_save"
    case noteSave = "note_save"
    case codeComment = "code_comment"
    case slackMessage = "slack_message"
    case teamsMessage = "teams_message"
    case discordMessage = "discord_message"
    case whatsappMessage = "whatsapp_message"
    case other = "other"

    public var qualityWeight: Double {
        switch self {
        case .emailCompose, .emailReply: return 1.0      // High intent, formal
        case .documentSave: return 0.9                   // Deliberate, polished
        case .noteSave: return 0.7                       // Personal, may be rough
        case .codeComment: return 0.6                    // Technical, constrained
        case .messageSend, .slackMessage, .teamsMessage,
             .discordMessage, .whatsappMessage: return 0.8 // Conversational but sent
        case .other: return 0.5
        }
    }
}

public enum WritingQuality: String, Codable, Sendable, CaseIterable {
    /// User explicitly sent/saved/kept this - HIGH QUALITY signal
    case adopted = "adopted"
    /// User deleted, discarded, or replaced this - NOISE signal
    case rejected = "rejected"
    /// In progress - not yet classified (exclude from learning)
    case draft = "draft"
}

public struct WritingMetadata: Codable, Sendable, Equatable {
    public var sentenceCount: Int = 0
    public var wordCount: Int = 0
    public var hasEmoji: Bool = false
    public var punctuation: PunctuationProfile = PunctuationProfile()
    public var formalityIndicators: FormalityIndicators = FormalityIndicators()

    public init() {}
}

public struct FormalityIndicators: Codable, Sendable, Equatable {
    public var passiveVoiceCount: Int = 0
    public var latinateWordRatio: Double = 0
    public var contractionRatio: Double = 0
    public var hedgeWordCount: Int = 0
    public var honorificCount: Int = 0

    public init() {}
}