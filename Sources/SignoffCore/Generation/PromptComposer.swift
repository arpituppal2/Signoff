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

    /// Empty voice profile snapshot — learning is disabled.
    public struct VoiceProfileSnapshot: Sendable {
        public let discriminativeFingerprint: [String: Double] = [:]
        public let noiseLexicalFingerprint: [String: Double] = [:]
        public let qualityPromptSummary: String = ""
        public let adoptedSignoffPatterns: [String] = []
        public let rejectedSignoffPatterns: [String] = []
        public let learningConsentGranted: Bool = false

        public init() {}
        public init(from _: VoiceProfile) {}
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
        ageGroup: AgeGroup? = nil,
        voiceProfile: VoiceProfileSnapshot? = nil,
        nsfwEnabled: Bool = false,
        attempt: Int = 1,
        usedMechanisms: [String] = []
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
            negativeExamples: template.negativeExamples,
            guardWords: template.guardWords,
            attempt: attempt,
            usedMechanisms: usedMechanisms)
        let variableTail = makeVariableTail(
            profile: profile,
            recentTexts: recentTexts,
            customInstructions: customInstructions,
            phraseList: phraseList,
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
    public static func makeInstructions(from template: PromptTemplate, ageGroup: AgeGroup = .genZ, voiceProfile: VoiceProfileSnapshot? = nil, nsfwEnabled: Bool = false) -> String {
        var parts: [String] = [template.system]
        // NOTE: AgeGroup voice instruction disabled temporarily to avoid
        // Apple SensitiveContentAnalysisML content filter (error 15)
        // let voice = ageGroup.voiceInstruction
        // if !voice.isEmpty {
        //     parts.append("Voice (this is the writer's generation — match it exactly):")
        //     parts.append(voice)
        // }

        // NOTE: We do NOT include template.rules in instructions because they
        /// contain banned-word lists that trigger Apple's SensitiveContentAnalysisML
        /// content filter (error 15). Guard words are validated post-generation instead.
        // if !template.rules.isEmpty {
        //     parts.append("Rules:")
        //     parts.append(contentsOf: template.rules.map { "- \($0)" })
        // }

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
        negativeExamples: [String],
        guardWords: [String] = [],
        attempt: Int = 1,
        usedMechanisms: [String] = []
    ) -> String {
        // DO NOT include examples - they seem to trigger content filter and banana fixation
        var sections: [String] = [userVariant]

        // Add corrective instruction on retries
        if attempt > 1 {
            var corrective = "PREVIOUS ATTEMPT REJECTED. You must produce a different, higher-quality signoff."
            if !usedMechanisms.isEmpty {
                corrective += " Do not use these mechanisms again: \(usedMechanisms.joined(separator: ", "))."
            }
            corrective += " Be concise. No narration. No quotes. No markdown."
            sections.append(corrective)
        }

        return sections.joined(separator: "\n\n")
    }

    /// Per-request context that must not enter the prewarm prefix.
    private static func makeVariableTail(
        profile: UserProfileSnapshot,
        recentTexts: [String],
        customInstructions: String?,
        phraseList: String?,
        voiceProfile: VoiceProfileSnapshot? = nil
    ) -> String {
        var sections: [String] = []

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

        if !profile.name.isEmpty {
            profileLines.append("Do not include the sender name \"\(profile.name)\".")
        }
        if !profileLines.isEmpty {
            sections.append(profileLines.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }
}