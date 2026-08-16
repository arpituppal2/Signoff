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
        preferredRegister: String? = nil
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
            curatedExamples: curatedExamples)
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
        curatedExamples: [String] = []
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
            sections.append("This register is: \(cue)")
        }

        // Use register-specific examples for few-shot if available
        let fewShotExamples = register?.examples ?? positiveExamples
        if !fewShotExamples.isEmpty {
            let exampleList = fewShotExamples.prefix(8).map { "- \($0)" }.joined(separator: "\n")
            sections.append("Examples of the exact feeling to channel — these are STYLE REFERENCES ONLY. Never output any of these lines verbatim, and never reuse their opening scaffold (e.g. \"Issued by my…\", \"Delivered by…\", \"Per my…\", \"With queso on top,\"). Invent a COMPLETELY NOVEL line in the same register:\n\(exampleList)")
        }

        // Add curated examples for additional few-shot prompting (positive only)
        if !curatedExamples.isEmpty {
            let exampleList = curatedExamples.map { "- \($0)" }.joined(separator: "\n")
            sections.append("Additional style examples:\n\(exampleList)")
        }

        // Add corrective instruction on retries
        if attempt > 1 {
            var corrective = "Previous attempt rejected. Produce a DIFFERENT, higher-quality signoff."
            if !usedMechanisms.isEmpty {
                corrective += " Avoid these registers: \(usedMechanisms.joined(separator: ", "))."
            }
            corrective += " Be concise. No narration. No quotes. No markdown. Do not copy any signoff from training or examples. Invent a FRESH one in the SAME emotional register. End with ONE COMMA. Capitalize ONLY the first word."
            sections.append(corrective)
        }

        // One-shot diversity nudge (first attempt)
        if attempt == 1 {
            sections.append("CRITICAL: Generate a FRESH signoff in the requested emotional register. Do NOT copy from any examples. End with ONE COMMA. Capitalize ONLY the first word.")
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

        // Avoid-list window: 8, not 6. The on-device 3B model fixates on
        // opener patterns, and a too-small window lets a rut-shape fall out
        // of view before the model rotates away from it (observed: the model
        // re-produced a phrase the moment it left the 6-window). An 8-window
        // keeps recent outputs — good (for shape rotation) and recently
        // rejected (for rut suppression) — visible long enough to break a rut
        // while still leaving room to generate. This is intentionally
        // NARROWER than the validator's rut-comparison window (suffix 12 for
        // Jaccard + opening/closing fingerprints) — the prompt avoid-list
        // tells the MODEL what not to repeat; the validator enforces
        // no-similarity against a broader recent burst. The earlier concern
        // that a wide window causes burst-exhaustion applies to the 8-attempt
        // hybrid slate (executeHybridGeneration), not the single-shot raw
        // generateRaw path, which has no retry slate to exhaust.
        let avoid = recentTexts
            .suffix(8)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !avoid.isEmpty {
            // Pink-elephant-resistant framing. A literal "do not repeat X, Y, Z"
            // ban-list foregrounds the exact tokens (e.g. "toaster") and the
            // 3B model fixates on them, copying the banned noun into the next
            // output ("Not signed by the toaster,"). Reframe the recent lines
            // as a STYLE REFERENCE and lead with the POSITIVE rotation
            // directive ("use a completely different subject/object/word"), so
            // the model's attention lands on "pick something new" rather than
            // on the noun we told it to avoid. The list still surfaces recent
            // phrases (required for dedup), but they read as exemplars to
            // diverge from, not forbidden tokens to obsess over.
            sections.append(
                "Recent signoffs — for style reference only. Write in the same kind of humor, "
                + "but use a COMPLETELY different subject on this line. Never reuse any concrete "
                + "object, name, catchphrase, or word that appears in any line below:\n"
                + avoid.map { "- \($0)" }.joined(separator: "\n"))
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