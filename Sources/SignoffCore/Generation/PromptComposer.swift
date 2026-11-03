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
        usedMechanisms: [String] = [],
        curatedExamples: [String] = [],
        preferredRegister: String? = nil,
        bucketId: String? = nil
    ) -> Composed {
        let instructions = makeInstructions(from: template)
        let (userVariant, selectedRegister) = chooseUserVariantAndRegister(
            template: template,
            unhingedLevel: unhingedLevel,
            toneValue: toneValue,
            postfixMode: postfixMode,
            usedMechanisms: usedMechanisms,
            preferredRegister: preferredRegister
        )
        // Stable head first (prewarmable), variable tail last.
        let promptPrefix = makePromptPrefix(
            userVariant: userVariant,
            positiveExamples: template.positiveExamples,
            register: selectedRegister,
            attempt: attempt,
            usedMechanisms: usedMechanisms,
            curatedExamples: curatedExamples,
            bucketId: bucketId)
        let effectiveRecentTexts = recentTexts
        let variableTail = makeVariableTail(
            profile: profile,
            recentTexts: effectiveRecentTexts,
            customInstructions: customInstructions,
            phraseList: phraseList,
            voiceProfile: voiceProfile,
            bucketId: bucketId,
            attempt: attempt
        )
        let prompt: String
        if variableTail.isEmpty {
            prompt = promptPrefix
        } else {
            prompt = promptPrefix + "\n\n" + variableTail
        }
        return Composed(instructions: instructions, prompt: prompt, promptPrefix: promptPrefix)
    }

    /// Builds the durable `instructions` string for the `LanguageModelSession`.
    /// Filter-safe: only the system persona. No rules, no voice instructions,
    /// no NSFW overrides — everything else triggers Apple's content filter (error 15).
    public static func makeInstructions(from template: PromptTemplate) -> String {
        template.system
    }

    /// Select the user variant and an emotional register for this generation.
    /// Returns the formatted user string (with {register} filled in) and the selected register.
    private static func chooseUserVariantAndRegister(
        template: PromptTemplate,
        unhingedLevel: UnhingedLevel? = nil,
        toneValue: Double? = nil,
        postfixMode: BucketPostfixMode? = nil,
        usedMechanisms: [String] = [],
        preferredRegister: String? = nil
    ) -> (String, PromptTemplate.Register?) {
        // Find matching user variant
        let matching = template.userVariants.filter { v in
            if let u = v.when.unhingedLevel, u != unhingedLevel?.rawValue { return false }
            if let range = v.when.toneRange, let tv = toneValue, !range.closed.contains(tv) { return false }
            if let p = v.when.postfixMode, p != postfixMode?.rawValue { return false }
            return true }
        let variant = matching.first?.user ?? "Write a single-sentence signoff that fits an editorial email."

        // Select register for emotional diversity (avoid recently used)
        let registers = template.registers ?? []
        var selectedRegister: PromptTemplate.Register? = nil
        if !registers.isEmpty {
            // Bias toward preferred register if available
            if let preferred = preferredRegister,
               let preferredRegisterObj = registers.first(where: { $0.name == preferred }) {
                selectedRegister = preferredRegisterObj
            } else {
                let available = registers.filter { !usedMechanisms.contains($0.name) }
                let pool = available.isEmpty ? registers : available
                selectedRegister = pool.randomElement()
            }
        }

        // Inject the register into the user variant template
        let registerName = selectedRegister?.name ?? ""
        let userPrompt = variant.replacingOccurrences(of: "{register}", with: registerName)

        return (userPrompt, selectedRegister)
    }

    /// Bucket-stable head shared by every request for a given variant.
    /// Register examples replace the flat positiveExamples for few-shot prompting.
    private static func makePromptPrefix(
        userVariant: String,
        positiveExamples: [String],
        register: PromptTemplate.Register?,
        attempt: Int = 1,
        usedMechanisms: [String] = [],
        curatedExamples: [String] = [],
        bucketId: String? = nil
    ) -> String {
        var sections: [String] = [userVariant]

        // Inject the register's human-readable feeling cue. Without this the
        // model only sees the hyphenated slug ("corporate-eyeroll") and infers
        // the register from its few-shot examples alone — which back-anchors
        // generation toward whatever imagery those examples share (e.g. email/
        // inbox for the office-themed cynical registers). The cue names the
        // *feeling* in plain English so the model channels it directly and the
        // witty registers (feigned-indifference, inverted-closer, …) actually
        // surface instead of being silently overridden by example themes.
        if let cue = register?.cue, !cue.isEmpty {
            sections.append("Tone: \(cue)")
        }

        // Use register-specific examples for few-shot if available
        let fewShotExamples = register?.examples ?? positiveExamples
        if !fewShotExamples.isEmpty {
            let examples = Array(fewShotExamples.prefix(GenerationTuning.fewShotExampleCount))
            let exampleList = examples.map { "- \($0)" }.joined(separator: "\n")
            sections.append("A few examples of the desired taste:\n\(exampleList)")
        }

        // Professional is a CLOSED vocabulary bucket: show the entire approved
        // menu so the model picks from it instead of inventing ("Formal
        // courtesy,"). The whitelist gate in GenerationService enforces this.
        if bucketId == BucketID.professional.rawValue, !positiveExamples.isEmpty {
            let menu = positiveExamples.map { "- \($0)" }.joined(separator: "\n")
            sections.append("APPROVED CLOSERS MENU — choose ONE line from this menu (or a trivial variant of one):\n\(menu)")
        }

        // Add curated examples for additional few-shot prompting (positive only)
        if !curatedExamples.isEmpty {
            let exampleList = curatedExamples.map { "- \($0)" }.joined(separator: "\n")
            sections.append("More examples:\n\(exampleList)")
        }

        // Add corrective instruction on retries
        if attempt > 1 {
            var corrective = "Try again with a different idea. Keep it natural, specific, and immediately understandable."
            if !usedMechanisms.isEmpty {
                corrective += " Avoid these registers: \(usedMechanisms.joined(separator: ", "))."
            }

            if bucketId == "standard" {
                corrective += " Generate a DIFFERENT, genuinely recognizable pop-culture reference from another film, TV show, meme, ad, song, game, or internet phrase. Do not write an original motivational sentence, compliment, or aphorism."
            } else if bucketId == BucketID.unhinged.rawValue {
                corrective += " Use one clean joke, not a pile of images. No narration, quotes, markdown, generic encouragement, or random nouns."
            } else if bucketId == BucketID.standard.rawValue {
                corrective += " Use a famous existing phrase. Do not invent or paraphrase one."
            } else {
                corrective += " Use one plain, familiar closing. Do not combine closers."
            }

            sections.append(corrective)
        }

        // One-shot diversity nudge (first attempt)
        if attempt == 1 && bucketId != BucketID.standard.rawValue {
            sections.append("Use one clear idea and stop. Output only the phrase.")
        } else if bucketId == "standard" {
            // Every attempt, not just the first — this is the failure mode
            // that matters for this bucket.
            sections.append("CRITICAL: The output MUST be a REAL quote, slogan, catchphrase, or meme a stranger would recognize. It must NOT be an original sentence you composed. Before answering, verify the source exists. If you cannot recall one, output your single favorite famous line instead of inventing.")
        }

        return sections.joined(separator: "\n\n")
    }

    /// Per-request context that must not enter the prewarm prefix.
    private static func makeVariableTail(
        profile: UserProfileSnapshot,
        recentTexts: [String],
        customInstructions: String?,
        phraseList: String?,
        voiceProfile: VoiceProfileSnapshot? = nil,
        bucketId: String? = nil,
        attempt: Int = 1
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

        if bucketId == BucketID.professional.rawValue {
            // Closed-vocabulary redirect: professional closers are a finite
            // menu, so explicitly naming recent ones steers sampling without
            // the pink-elephant effect seen on creative buckets. Without
            // this the model re-emits favorites until every gate blocks it
            // and the retry loop exhausts.
            let recentClosers = recentTexts.suffix(GenerationTuning.professionalAvoidListDepth)
            if !recentClosers.isEmpty {
                let listed = recentClosers.map { "- \($0)" }.joined(separator: "\n")
                sections.append("Closers ALREADY USED in this conversation — do NOT repeat them or trivial variants of them:\n\(listed)")
            }
        }

        if bucketId == BucketID.unhinged.rawValue {
            // Anchor rotation. The on-device 3B cannot reliably SUMMON a
            // recognizable phrase to twist from nothing — left abstract it
            // defaults to lazy scaffolds ("All X, no Y", random provenance
            // salad). But it CAN reliably twist a phrase it is handed. So the
            // rotation feeds it a concrete recognizable idiom/line to subvert
            // per attempt (raw material, NOT a finished signoff — this is not
            // a bank). A handful of mechanism lanes stay in the rotation so
            // the non-phrase ground-truth categories (inverted closer,
            // impossible premise) still get exercised. Rotating per attempt
            // means every retry gets a fresh anchor, which both diversifies
            // output and pulls the model off the "All X, no Y" attractor.
            let anchors = [
                "Twist this recognizable phrase into a signoff: 'break a leg'",
                "Twist this recognizable phrase into a signoff: 'the early bird gets the worm'",
                "Politely subvert a formal closer so it is obviously sarcastic",
                "Twist this recognizable phrase into a signoff: 'when life gives you lemons'",
                "Twist this recognizable phrase into a signoff: 'a watched pot never boils'",
                "Make a light impossible-premise joke about yourself",
                "Twist this recognizable phrase into a signoff: 'actions speak louder than words'",
                "Twist this recognizable phrase into a signoff: 'curiosity killed the cat'",
                "Claim an absurd 'sent from' origin with one specific silly detail",
                "Twist this recognizable phrase into a signoff: 'the ball is in your court'",
                "Twist this recognizable phrase into a signoff: 'burn the midnight oil'",
                "Use a recognizable pop-culture callback as the punchline",
                "Twist this recognizable phrase into a signoff: 'every cloud has a silver lining'",
                "Twist this recognizable phrase into a signoff: 'let sleeping dogs lie'",
            ]
            let index = abs((attempt - 1) % anchors.count)
            sections.append("\(anchors[index]). One clean twist, then stop.")
        }

        // NOTE: there is deliberately NO "recent signoffs / avoid-list" block
        // for ANY bucket. Feeding the model its own recent lines as a "never
        // reuse these words" list triggers the pink-elephant effect on the
        // on-device 3B model (it foregrounds and copies the very words it's
        // told to avoid), which is the root cause of the repetition complaint.
        // Repetition is enforced deterministically AFTER generation in
        // GenerationService.mechanicalRejectReason (exact + near-dup Jaccard
        // + skeleton collision against recent history), which re-rolls until
        // a fresh line surfaces.

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