import Foundation

/// Builds Foundation Models Instructions (stable, cacheable) separately from
/// the per-request Prompt (user data, recents, profile). Never put user data
/// into Instructions — that would bust prewarm prefix caching and leak PII
/// into the session's durable instruction text.
///
/// `promptPrefix` is always a true prefix of `prompt` so
/// `session.prewarm(promptPrefix:)` caches tokens that every request shares.
public enum PromptComposer: Sendable {

    public struct Composed: Sendable, Equatable {
        /// Stable system + rules text for `LanguageModelSession(instructions:)`.
        public let instructions: String
        /// Per-request user prompt (variant + examples + variable context).
        public let prompt: String
        /// Stable prefix of `prompt` suitable for `session.prewarm(promptPrefix:)`.
        public let promptPrefix: String

        public init(instructions: String, prompt: String, promptPrefix: String) {
            self.instructions = instructions
            self.prompt = prompt
            self.promptPrefix = promptPrefix
        }
    }

    /// Sendable snapshot of voice profile data needed for composition.
    /// This allows background tasks to compose prompts without capturing
    /// the non-Sendable VoiceProfile class.
    public struct VoiceProfileSnapshot: Sendable {
        public let discriminativeFingerprint: [String: Double]
        public let noiseLexicalFingerprint: [String: Double]
        public let qualityPromptSummary: String
        public let adoptedSignoffPatterns: [String]
        public let rejectedSignoffPatterns: [String]
        public let learningConsentGranted: Bool

        public init(
            discriminativeFingerprint: [String: Double],
            noiseLexicalFingerprint: [String: Double],
            qualityPromptSummary: String,
            adoptedSignoffPatterns: [String],
            rejectedSignoffPatterns: [String],
            learningConsentGranted: Bool
        ) {
            self.discriminativeFingerprint = discriminativeFingerprint
            self.noiseLexicalFingerprint = noiseLexicalFingerprint
            self.qualityPromptSummary = qualityPromptSummary
            self.adoptedSignoffPatterns = adoptedSignoffPatterns
            self.rejectedSignoffPatterns = rejectedSignoffPatterns
            self.learningConsentGranted = learningConsentGranted
        }

        /// Create from a VoiceProfile on the main actor.
        public init(from voiceProfile: VoiceProfile) {
            self.discriminativeFingerprint = voiceProfile.discriminativeFingerprint
            self.noiseLexicalFingerprint = voiceProfile.noiseLexicalFingerprint
            self.qualityPromptSummary = voiceProfile.qualityPromptSummary
            self.adoptedSignoffPatterns = voiceProfile.adoptedSignoffPatterns
            self.rejectedSignoffPatterns = voiceProfile.rejectedSignoffPatterns
            self.learningConsentGranted = voiceProfile.learningConsentGranted
        }
    }

    public static func compose(
        template: PromptTemplate,
        profile: UserProfileSnapshot,
        recentTexts: [String],
        unhingedLevel: UnhingedLevel? = nil,
        toneValue: Double? = nil,
        postfixMode: BucketPostfixMode? = nil,
        customInstructions: String? = nil,
        phraseList: String? = nil,
        contextInstructions: String? = nil,
        ageGroup: AgeGroup? = nil,
        voiceProfile: VoiceProfileSnapshot? = nil,
        nsfwEnabled: Bool = false
    ) -> Composed {
        let instructions = makeInstructions(from: template, ageGroup: ageGroup ?? .genZ, voiceProfile: voiceProfile, nsfwEnabled: nsfwEnabled)
        let userVariant = template.chooseUser(
            unhingedLevel: unhingedLevel,
            toneValue: toneValue,
            postfixMode: postfixMode
        )
        // Stable head first (prewarmable), variable tail last.
        let promptPrefix = makePromptPrefix(
            userVariant: userVariant,
            positiveExamples: template.positiveExamples,
            negativeExamples: template.negativeExamples
        )
        let variableTail = makeVariableTail(
            profile: profile,
            recentTexts: recentTexts,
            customInstructions: customInstructions,
            phraseList: phraseList,
            contextInstructions: contextInstructions,
            voiceProfile: voiceProfile
        )
        let prompt: String
        if variableTail.isEmpty {
            prompt = promptPrefix + "\n\nRespond with only the signoff text."
        } else {
            prompt = promptPrefix + "\n\n" + variableTail + "\n\nRespond with only the signoff text."
        }
        return Composed(instructions: instructions, prompt: prompt, promptPrefix: promptPrefix)
    }

    /// Builds the durable `instructions` string for the `LanguageModelSession`.
    /// The age-group voice instruction is folded in here so it becomes part of
    /// the stable, prewarmable prefix — the whole point of the anti-cringe lever.
    ///
    /// NEW: Injects the discriminative voice fingerprint — quality patterns BOOSTED,
    /// noise patterns SUPPRESSED. This is the "secret sauce" that makes signoffs
    /// sound like the user's BEST writing, not their average writing.
    public static func makeInstructions(from template: PromptTemplate, ageGroup: AgeGroup = .genZ, voiceProfile: VoiceProfileSnapshot? = nil, nsfwEnabled: Bool = false) -> String {
        var parts: [String] = [template.system]
        // Voice first: it's the strongest lever and stays consistent across
        // every request for a given user, so it belongs in the stable prefix.
        let voice = ageGroup.voiceInstruction
        if !voice.isEmpty {
            parts.append("Voice (this is the writer's generation — match it exactly):")
            parts.append(voice)
        }

        // Inject discriminative voice fingerprint if available
        if let vp = voiceProfile, vp.learningConsentGranted {
            let fingerprint = vp.discriminativeFingerprint
            if !fingerprint.isEmpty {
                parts.append("WRITING STYLE FINGERPRINT (learned from your actual writing — quality patterns amplified, rejected patterns suppressed):")
                let topQuality = fingerprint
                    .filter { $0.value > 0 }
                    .sorted { $0.value > $1.value }
                    .prefix(8)
                    .map { "\"\($0.key)\" (weight: \(String(format: "%.2f", $0.value)))" }
                    .joined(separator: ", ")

                let topNoise = vp.noiseLexicalFingerprint
                    .sorted { $0.value > $1.value }
                    .prefix(4)
                    .map { "\"\($0.key)\" (AVOID — user deletes this pattern)" }
                    .joined(separator: ", ")

                if !topQuality.isEmpty {
                    parts.append("Patterns you naturally use: \(topQuality)")
                }
                if !topNoise.isEmpty {
                    parts.append("Patterns you actively avoid: \(topNoise)")
                }

                // qualityPromptSummary is non-optional; it always returns a string (possibly empty)
                let summary = vp.qualityPromptSummary
                if !summary.isEmpty {
                    parts.append("Your voice summary: \(summary)")
                }
            }
        }

        if !template.rules.isEmpty {
            parts.append("Rules:")
            parts.append(contentsOf: template.rules.map { "- \($0)" })
        }

        // Cynical bucket only: when the user opts into NSFW, explicitly lift the
        // template's profanity/sexual-content bans. Always keep it witty, never
        // hateful, violent, or targeted. Appended last so it reads as the final
        // binding instruction.
        if nsfwEnabled {
            parts.append("Content policy override: profanity and adult humor are permitted in this request.")
        }
        return parts.joined(separator: "\n")
    }

    /// Bucket-stable head shared by every request for a given variant.
    private static func makePromptPrefix(
        userVariant: String,
        positiveExamples: [String],
        negativeExamples: [String]
    ) -> String {
        var sections: [String] = [userVariant]
        if !positiveExamples.isEmpty {
            sections.append("Good examples: " + positiveExamples.joined(separator: " / "))
        }
        if !negativeExamples.isEmpty {
            sections.append("Avoid: " + negativeExamples.joined(separator: " / "))
        }
        return sections.joined(separator: "\n\n")
    }

    /// Per-request context that must not enter the prewarm prefix.
    private static func makeVariableTail(
        profile: UserProfileSnapshot,
        recentTexts: [String],
        customInstructions: String?,
        phraseList: String?,
        contextInstructions: String? = nil,
        voiceProfile: VoiceProfileSnapshot? = nil
    ) -> String {
        var sections: [String] = []

        if let ctx = contextInstructions?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ctx.isEmpty {
            sections.append(ctx)
        }

        if let custom = customInstructions?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            sections.append("Custom instructions:\n\(custom)")
        }
        if let list = phraseList?.trimmingCharacters(in: .whitespacesAndNewlines),
           !list.isEmpty {
            sections.append("Phrase list:\n\(list)")
        }

        let avoid = recentTexts
            .suffix(12)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !avoid.isEmpty {
            sections.append("Avoid repeating these recent phrases:\n" + avoid.map { "- \($0)" }.joined(separator: "\n"))
        }

        var profileLines: [String] = []
        if !profile.selfDescription.isEmpty {
            profileLines.append("Voice: \(profile.selfDescription)")
        }

        // Inject adopted vs rejected signoff patterns from voice profile
        if let vp = voiceProfile, vp.learningConsentGranted {
            let adopted = vp.adoptedSignoffPatterns.suffix(3)
            let rejected = vp.rejectedSignoffPatterns.suffix(2)

            if !adopted.isEmpty {
                profileLines.append("Signoffs you actually use: \(adopted.joined(separator: " | "))")
            }
            if !rejected.isEmpty {
                profileLines.append("Signoffs you delete/replace: \(rejected.joined(separator: " | ")) — AVOID these")
            }
        }

        if !profile.name.isEmpty {
            profileLines.append("Do not include the sender name \"\(profile.name)\".")
        }
        if !profileLines.isEmpty {
            sections.append(profileLines.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }
}