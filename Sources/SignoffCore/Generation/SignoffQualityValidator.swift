import Foundation
import RegexBuilder

/// Local quality validator for generated signoffs
@MainActor
public final class SignoffQualityValidator: ObservableObject {
    public static let shared = SignoffQualityValidator()

    // Banned words/patterns that indicate low quality
    private let bannedTokens: Set<String> = [
        "premium", "text matrix", "matrix",
        "forgotten", "fourth eye", "4th eye",
        "dreaming", "keyboard dreams",
        "lol",
        "ghost inbox", "phantom priorit", "stale optim",
        "typing feels like", "traffic prefers", "counting sheep",
        "collaboration felt", "valued input", "steady groove",
        "steady rhythm", "synergy", "journey", "path forward",
        "vision", "meaningful dialogue", "grateful for the opportunity",
        "transformative", "partnership", "appreciate the clarity",
        "looking forward to continued collaboration", "inbox fumes",
        "feeding on stale", "running on ghost", "running on phantom",
        // Word salad fragments
        "all strings", "no vowels", "looks like spam", "not mail",
        "familiar not fancy", "all strings", "no coffee",
        "understood not", "deadpan code", "yours totally",
        "looks like code", "fake fax", "deadpan the email",
        "confused but", "bounced from", "your inbox", "your code",
        "your bandwidth", "with pixels", "with all caps", "your turn",
        "your data", "your cipher", "your blueprint", "your wallet",
        "your email", "made from", "changed not", "outsourced but",
        "edited by", "interrupted by", "no strings", "deadly format",
        "deadly optimism", "deadly silence", "junk mail", "bottom line",
        "tightrope zero", "chaos mode", "all scroll",
        // Additional word salad patterns from recent failures
        "code not coffee", "syntax not soul", "bits not banter",
        "no coffee just vibes", "just vibes no code", "all nouns no verbs",
        "familiar not fancy genius", "all strings no vowels",
        // Deadpan abuse
        "deadpan,", "deadpan totally", "deadpan exclamation", "deadpan zero",
        "deadpan glitch", "deadpan bogus", "deadpan algorithm",
        "deadpan typo", "deadpan keyboard", "deadpan neurons",
        "deadpan debugging", "deadpan ignored", "deadpan seriously",
        "deadpan code", "deadpan lost", "deadpan existential",
        "deadpan puzzle", "deadpan activated",
        // Fake inbox variants
        "faux inbox", "fake inbox", "phony inbox", "faux urgency", "faux code",
        // Deadly template family
        "deadly code", "deadly syntax", "deadly pixels", "deadly algorithm",
        "deadly plot", "deadly meme", "deadly data", "deadly toast",
        "deadly sarcasm", "deadly metaphor", "deadly handshake",
        // Fake tech templates
        "fake server", "fake algorithm",
        // Overused phrases
        "hasta la pasta"
    ]

    // Banned n-gram patterns (2-3 word sequences that indicate template reuse)
    private let bannedNGrams: Set<String> = [
        "felt natural", "aligned effortlessly", "valued input shaped",
        "collaboration felt", "steady rhythm", "steady groove",
        "ghost inbox", "phantom priorities", "stale optimism",
        "inbox fumes", "feeding on stale", "feeding on phantom",
        "premium", "text matrix", "forgotten", "fourth eye",
        "keyboard dreams"
    ]

    // Minimum/maximum word counts per bucket — short by design. The model
    // drifts long with loose limits, so these are tight caps the validator
    // enforces on every candidate (live and curated).
    private let wordCountLimits: [String: ClosedRange<Int>] = [
        "standard": 1...7,
        "unhinged": 2...7,
        "professional": 1...4
    ]

    // Maximum similarity threshold (0.0 - 1.0). 0.78 is tight enough to
    // block near-duplicates but loose enough that two distinct short lines
    // sharing an opener word ("Officially X," / "Officially Y,") don't both
    // get rejected — the opening-bigram fingerprint already catches
    // same-opener ruts, so jaccard only needs to catch true near-dups.
    private let maxSimilarityThreshold: Double = 0.78

    private init() {}

    /// Concrete common-noun set — GATE-INTERNAL ONLY. Never surfaced to the
    /// model prompt (that would amplify the very tokens it catches — the
    /// pink-elephant effect we hit when a "STYLE DIVERGE: avoid banana, …"
    /// directive produced "Banana peel under the umbrella," naming BOTH banned
    /// nouns in one output). This list lives only inside `validate()`; the
    /// model never sees it, so enumerating banana does NOT anchor the model on
    /// banana. The 3B has a LATENT food/everyday-object fixation (banana,
    /// cheese, umbrella, blender, toaster recur across prompt edits with no
    /// prompt-side anchor) that surfaces as bare 2-3-word noun-stack closers
    /// ("Banana peel," / "Banana split," / "Banana in the blender,"). The
    /// short-tier gate (below) catches these by shape, fruit/modest — we add
    /// tokens only as new concrete-nouns are observed fixating; this is
    /// open-ended by design (a complete English-noun list would over-fire on
    /// legitimate noun-closers like "Toaster," as a real deadpan object).
    private let concreteNounSet: Set<String> = [
        // fruits
        "banana", "plantain", "mango", "papaya", "kiwi", "lemon", "lime",
        "orange", "peach", "plum", "pear", "apple", "grape", "melon", "fig",
        // dessert/food (the 3B's fixation cluster)
        "cheese", "toast", "toaster", "waffle", "pancake", "bagel", "muffin",
        "cookie", "brownie", "pudding", "custard", "jelly", "jam", "queso",
        "nacho", "nachos", "taco", "burrito", "pasta", "noodle", "soup", "stew",
        "salad", "cereal", "oatmeal", "yogurt",
        // drinks
        "coffee", "tea", "soda", "juice", "smoothie", "milkshake", "latte",
        // animals
        "llama", "pug", "panda", "penguin", "otter", "goose", "duck",
        // everyday objects (3B fixation cluster)
        "umbrella", "blender", "toaster", "fridge", "pillow", "blanket",
        "spoon", "fork", "napkin", "crayon", "ladder", "helmet", "whisk",
        // body parts
        "nose", "elbow", "ankle", "nostril", "eyebrow",
        // food parts (the peel/peel/skin/salad fixation)
        "peel", "rind", "crust", "skin"
    ]

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

        // 4. Model narration check — the model sometimes prefixes its output
        // with a meta label ("REVISED: …", "REVIEWED: …", "EDIT: …"). These
        // read as a bug/glitch, not a signoff, and would never appear in a
        // real closer. Also catches the classic "Here's one:" scaffolding.
        let narrationPatterns = [
            "signoff:", "here's one:", "here is one:",
            "here's a signoff:", "here is a signoff:",
            "output:", "result:", "generated:",
            "i would say:", "i'd say:", "you could use:",
            "revised:", "reviewed:", "edited:", "edited:", "draft:",
            "version:", "v2:", "v1:", "alt:", "option:", "try:"
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
        // Reject actual markdown formatting, not single asterisk emphasis
        if trimmed.contains("**") || trimmed.contains("#") || trimmed.contains("`") {
            return .invalid(reason: "Contains markdown formatting")
        }
        // Check for markdown list markers at start of line
        if trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ") || trimmed.hasPrefix("1. ") {
            return .invalid(reason: "Contains markdown list formatting")
        }

        // 6. Banned tokens check (word-boundary aware to avoid false positives)
        for token in bannedTokens {
            let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: token.lowercased()) + #"\b"#
            let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(location: 0, length: lowercased.utf16.count)
            if regex.firstMatch(in: lowercased, options: [], range: range) != nil {
                return .invalid(reason: "Contains banned token: \(token)")
            }
        }

        // 7. Question mark check - signoffs must not end with question marks
        if trimmed.hasSuffix("?") {
            return .invalid(reason: "Ends with question mark")
        }

        // 8. Template pattern check - only genuinely sloppy templates (deadly*, faux*)
        let templatePatterns = [
            #"^deadly \w+,* \w+"#,       // "Deadly code,", "Deadly syntax,"
            #"^faux \w+,* \w+"#,         // "Faux urgency", "Faux code"
        ]
        for pattern in templatePatterns {
            let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(location: 0, length: lowercased.utf16.count)
            if regex.firstMatch(in: lowercased, options: [], range: range) != nil {
                return .invalid(reason: "Contains template pattern: \(pattern)")
            }
        }

        // 9. Banned n-grams check
        for ngram in bannedNGrams {
            if lowercased.contains(ngram.lowercased()) {
                return .invalid(reason: "Contains banned n-gram: \(ngram)")
            }
        }

        // 9a. "Sent from X" / "Sent with X" auto-signature family ban — applies
        // to ALL buckets. The user's verbatim rule: "cut all of sent from ___
        // or sent with ___ except for sent from my pillow fort, all of them
        // suck." These read as stock email-client footer clichés ("Sent from
        // my iPhone,"), not as wit. A single carve-out survives: lines
        // containing "pillow fort" (the one blessed absurdist variant). The
        // ban is a substring on the 2-gram, which is the tic signature itself.
        if lowercased.contains("sent from") || lowercased.contains("sent with") {
            if !lowercased.contains("pillow fort") {
                return .invalid(reason: "Contains 'Sent from/with X' auto-signature cliché (only 'Sent from my massive pillow fort,' is allowed)")
            }
        }

        // Literal-body-death idiom ban — applies to ALL buckets but exists
        // for the unhinged bucket, which drifts toward melodramatic physical-
        // destruction imagery. The user's verbatim rule, after "On the verge
        // of spontaneous combustion," surfaced: "That's just a mental health
        // concern, not funny." A follow-up diagnostic ("Officially
        // suffocating, just existing,") confirmed the same class: idioms of
        // LITERAL death of the body — burning alive, asphyxiation — read as
        // genuine distress, not satire. Combined with the CEO test (a serious
        // exec typing it literally would alarm recipients) and rule 6 (if
        // taken literally, reject), these must never surface.
        // Banned families:
        //   • Fire/immolation: combustion, burning, blazing, ignite,
        //     incinerate, immolate, "up in flames", "on fire"
        //   • Asphyxiation: suffocate, asphyxia, smother
        // KEY DISTINCTION — literal body-death (BANNED) vs recognized
        // metaphor for busyness/tiredness (KEPT): "drowning in spreadsheets"
        // is a recognized metaphor; "suffocating" / "combusting" are NOT
        // idioms for busyness — they are literal ways bodies die, so they
        // read as distress. We keep "drowning in [work]", "bleeding
        // patience" (idiom), "running on fumes", "crumbling" and ban only
        // literal body-death. Tokens are distinctive enough that substring/
        // word-boundary matching has zero collateral.
        let literalDistressTokens = [
            // fire/immolation family
            "combust", "burning", "blazing",
            "ignit", "incinerat", "immolat",
            "up in flames", "on fire",
            // asphyxiation family (suffocate/suffocating/suffocated, asphyxia,
            // smother/smothering) — same literal-body-death class as fire
            "suffocat", "asphyxia", "smother"
        ]
        for token in literalDistressTokens {
            // Stems (end in a consonant cluster that mutates across forms:
            // combust/combustion, ignit/ignite, suffocat/suffocating) use
            // substring matching to catch all inflections. Full words /
            // phrases (burning, blazing, "up in flames", "on fire") use
            // word boundaries so "on fire" does NOT false-positive on
            // "on firewalls," — substring would catch the longer compound.
            let isStem = ["combust", "ignit", "incinerat", "immolat",
                          "suffocat", "asphyxia", "smother"].contains(token)
            if isStem {
                if lowercased.contains(token) {
                    return .invalid(reason: "Contains literal-body-death idiom '\(token)' — reads as mental-health distress, not satire (CEO/rule-6 test)")
                }
            } else {
                let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: token) + #"\b"#
                let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                let range = NSRange(location: 0, length: lowercased.utf16.count)
                if regex.firstMatch(in: lowercased, options: [], range: range) != nil {
                    return .invalid(reason: "Contains literal-body-death idiom '\(token)' — reads as mental-health distress, not satire (CEO/rule-6 test)")
                }
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

        // 9. Rut checks (similarity + shape fingerprints) — compare against a
        // 12-output window matching the prompt's avoid-list (`suffix(12)` in
        // PromptComposer.makeVariableTail). Comparing against the FULL history
        // (which grows across a batch) over-pressures late iterations: by
        // output #40 nearly every shape is "used" and every attempt exhausts.
        // The consecutive-rut behavior we want to kill is back-to-back
        // repetition within the recent window — a template reappearing 20
        // generations later is fine. Exact-dup above stays on full history.
        let recentWindow = Array(recentHistory.suffix(12))

        // High similarity check against recent window
        for recent in recentWindow {
            let similarity = jaccardSimilarity(normalizedCandidate, normalizeForComparison(recent))
            if similarity > maxSimilarityThreshold {
                return .invalid(reason: "Too similar to recent signoff (similarity: \(String(format: "%.2f", similarity)))")
            }
        }

        // 9b. Shape-similarity check — catches template-rotation that
        // word-overlap misses. Two failure modes the fingerprints handle:
        //   (a) Fixed opening, rotating tail noun: "With thoughtful thanks,"
        //       / "With thoughtful regard," — OPENING bigram ("with thoughtful …").
        //   (b) Fixed closing suffix, rotating opening: "…, barely," —
        //       CLOSING token for 5+ token lines.
        // We deliberately do NOT fingerprint the coarse grammatical skeleton
        // ("X X in X"): English is grammatically repetitive, and a shape
        // fingerprint over-fires — distinct legitimate lines share "X X the X"
        // and would all be rejected, halving yield. The opening/closing
        // fingerprints plus the prompt-side template ban catch real ruts
        // without rejecting valid variety.
        if !recentWindow.isEmpty {
            let openFP = openingFingerprint(trimmed)
            let closeFP = closingFingerprint(trimmed)
            for recent in recentWindow {
                if let o = openFP, o == openingFingerprint(recent) {
                    return .invalid(reason: "Same opening shape as recent signoff (template rotation: '\(o)')")
                }
                if let c = closeFP, c == closingFingerprint(recent) {
                    return .invalid(reason: "Same closing tic as recent signoff (template rotation: '\(c)')")
                }
            }
            // Opener-word + closing-token frequency caps were TRIED and
            // REVERTED: they killed the "Officially X" fixation rut but raised
            // the per-attempt rejection rate enough to cause 8-attempt
            // exhaustion FAILs (diag4 18/20, diag5 16/20 — worse than the
            // 19/20 baseline with no caps). The 3B on-device model fixates on
            // opener words; when a cap blocks the fixation it regenerates the
            // same blocked shape 8× and exhausts. The fingerprint checks above
            // (exact 2-token open bigram, 5+-token last token) catch the
            // dominant ruts with far lower false-positive pressure. We keep
            // diversity via prompt instruction + register-cycling in
            // GenerationService rather than hard validator caps.
        }

        // 10. Mechanism diversity check (don't repeat same mechanism too often)
        // This is a soft check - we just track it

        // 11. Bucket-specific checks
        if bucketId == "professional" {
            // Professional must not have jokes, twists, or casual language.
            // Word-boundary matched so "Standing by," does NOT false-positive
            // on "stan" (the overzealous-fan slang) — substring matching did,
            // and wrongly rejected a perfectly fine closer.
            let professionalBanned = ["lol", "haha", "lmao", "omg", "wtf", "bruh", "dude", "bro",
                                       "cowabunga", "smell ya", "allegedly", "yolo", "fam",
                                       "squad", "goals", "mood", "vibes", "slay", "stan"]
            for banned in professionalBanned {
                let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: banned) + #"\b"#
                let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                let range = NSRange(location: 0, length: lowercased.utf16.count)
                if regex.firstMatch(in: lowercased, options: [], range: range) != nil {
                    return .invalid(reason: "Professional bucket contains inappropriate term: \(banned)")
                }
            }
            // Ban the "Deep thanks," / "Deep respect," / "Deep gratitude,"
            // family — this is an LLM tic, not a real professional convention.
            // Actual closers are "Best," "Thanks," "Sincerely," "Best regards,".
            let deepRegex = try! NSRegularExpression(pattern: #"^\bdeep\b \w+"#, options: [.caseInsensitive])
            let deepRange = NSRange(location:0, length: lowercased.utf16.count)
            if deepRegex.firstMatch(in: lowercased, options: [], range: deepRange) != nil {
                return .invalid(reason: "Professional bucket contains LLM-tic 'Deep X' closer (not a real convention)")
            }
        }

        // Initial-capitalization check (all buckets): the first character of a
        // sendable signoff should be an uppercase letter. The model occasionally
        // emits a lowercase opener ("deep thanks,", "yours, suspiciously,") which
        // reads as a typo. Allow a leading quote → capitalized letter after it.
        if let firstChar = trimmed.first, firstChar.isLetter, !firstChar.isUppercase {
            // Single-word lowercase closers like "yours," are conventional and
            // fine — only flag when there are 2+ words (a real sentence shape).
            if wordCount >= 2 {
                return .invalid(reason: "Signoff starts with a lowercase letter (capitalization required)")
            }
        }
        // ALL-CAPS check (all buckets): when fixated, the model occasionally
        // flips to shout-formatting ("THANK YOU, sincerely," / "REGARDS, Sincerely,") which reads
        // as a bug, not wit. A signoff capitalizes only the FIRST word; a first word
        // that is fully uppercase is a rut artifact. Single-word ALL-CAPS closers
        // like "BEST," "THANKS," "REGARDS," are not real email conventions — they
        // read as a glitch. Check ALL word counts (including 1-word closers).
        let allWords = trimmed.split { $0.isWhitespace || $0 == "," || $0 == "." }
            .map { String($0) }
            .filter { $0.contains { $0.isLetter } }
        if let firstWord = allWords.first {
            let firstWordIsAllUpper = firstWord.contains { $0.isLetter } && firstWord.filter { $0.isLetter }.allSatisfy { $0.isUppercase }
            if firstWordIsAllUpper {
                return .invalid(reason: "Signoff first word is ALL-CAPS (shout formatting) — capitalize only the first word")
            }
        }

        // Invented -ly adverb check (all buckets): the model invents forms like
        // "regretfully," "professionally," "honestly," "muchly," "regardingly"
        // by adding -ly to adjectives. These are NOT real email closers.
        // Check if the final word (before punctuation) ends in -ly and has 5+ letters
        // (to allow real -ly words like "sincerely" which IS a conventional closer).
        // "Muchly" (7 letters, not a real word) gets caught; "sincerely" (9, real) passes.
        if let lastWord = allWords.last {
            let lastWordLower = lastWord.lowercased()
            if lastWordLower.hasSuffix("ly") && lastWordLower.count >= 5 {
                let knownRealLy = ["sincerely", "cordially", "respectfully", "gratefully", "faithfully", "truly", "warmly", "kindly", "really", "surprisingly"]
                if !knownRealLy.contains(lastWordLower) {
                    return .invalid(reason: "Signoff ends with invented -ly adverb '\(lastWord)' — not a real email closer")
                }
            }
        }

        // Multiple-closer combination check (professional bucket): the model
        // sometimes combines two closers like "Warm, my regards," or "Thanks, best,"
        // Real professional emails use EXACTLY ONE closer. Detect by counting
        // conventional closer tokens in the output.
        if bucketId == "professional" {
            let professionalCloserTokens = [
                "best", "thanks", "regards", "sincerely", "respectfully", "cordially",
                "warm", "kind", "warmly", "kindly", "yours", "faithfully", "truly",
                "appreciate", "gratitude", "talk", "speak", "see", "take", "hope",
                "enjoy", "have", "stay", "be", "keep", "wish", "cheers", "cheerio",
                "ciao", "later", "soon", "then", "care", "well", "strong", "safe",
                "thrive", "rest", "easy", "calm", "in", "with", "all", "my", "of",
                "for", "the", "to", "your", "our", "your", "its", "from"
            ]
            // Heuristic: if we see 3+ tokens that are typical closer words,
            // it's likely combining multiple closers. Also catch the specific
            // "Warm, my regards" pattern: 3 words where 2 are close-phrases.
            // More robust: check for comma-separated multiple phrases that are
            // each conventional closers on their own.
            if allWords.count >= 3 {
                // Look for pattern: "Warm, my regards" -> ["Warm", "my", "regards"]
                // Both "warm" and "regards" are closer words, "my" is connective
                let closerWordsInOutput = allWords.filter { professionalCloserTokens.contains($0.lowercased()) }.count
                if closerWordsInOutput >= 2 {
                    // But allow "Best regards" (2 words, conventional pair)
                    // and "Kind regards" etc. Check if it matches a known pair
                    let knownPairs = [
                        "best regards", "kind regards", "warm regards", "warm wishes",
                        "kind wishes", "sincerely yours", "yours truly", "yours sincerely",
                        "yours faithfully", "respectfully yours", "cordially yours",
                        "very truly yours", "all best", "all the best", "my best",
                        "best wishes", "talk soon", "speak soon", "see soon",
                        "talk later", "see later", "until then", "see then",
                        "take care", "have a", "enjoy your", "hope this",
                        "stay well", "be well", "keep well", "stay in", "keep in",
                        "thanks for", "thank you", "many thanks", "thanks again",
                        "with thanks", "with gratitude", "with appreciation",
                        "warm thanks", "kind thanks", "much appreciated",
                        "best of", "kind of", "warmly", "sincerely", "respectfully",
                        "cordially", "faithfully", "truly", "yours", "regards"
                    ]
                    let outputLower = trimmed.lowercased()
                    let matchesKnownPair = knownPairs.contains { outputLower.hasPrefix($0) || outputLower.contains(" \($0)") }
                    if !matchesKnownPair && closerWordsInOutput >= 2 {
                        return .invalid(reason: "Professional signoff combines multiple closers — use exactly one conventional closer")
                    }
                }
            }
        }

        if bucketId == "unhinged" {
            // Cynical must not be genuinely hostile or unsafe
            let unsafePatterns = ["kill yourself", "kys", "die", "suicide", "harm yourself",
                                 "hate you", "fuck you", "go die", "nobody likes",
                                 "worthless", "pathetic", "garbage human",
                                 // Off-color biology/masculinity jokes — not sendable office humor
                                 "testosterone", "hormones", "hormone"]
            for unsafe in unsafePatterns {
                if lowercased.contains(unsafe) {
                    return .invalid(reason: "Cynical bucket contains unsafe content: \(unsafe)")
                }
            }
            // Reject the directed possessive "your" — it turns the line into a
            // jab at the recipient ("Your enthusiasm is a spreadsheet glitch,",
            // "Your agenda? Another spreadsheet,") which reads as demeaning or
            // attacking the reader. The self-reference closer "Yours," /
            // "Grudgingly yours," is preserved: the \byour\b word boundary does
            // NOT match "yours" (the "s" is a word char, so there is no
            // boundary between "your" and "s"). Cynicism here is about life,
            // the situation, or the writer's own state — never an attack on the
            // reader.
            let yourRegex = try! NSRegularExpression(pattern: #"\byour\b"#, options: [.caseInsensitive])
            let yourRange = NSRange(location: 0, length: lowercased.utf16.count)
            if yourRegex.firstMatch(in: lowercased, options: [], range: yourRange) != nil {
                return .invalid(reason: "Cynical signoff directs possessive 'your' at recipient (demeaning)")
            }
            // Reject the ", the X" / ", a X" / ", an X" personification-clause
            // rut. The model's dominant collapse mode is a two-clause line:
            // a worn-down state, then a comma, then a personified noun phrase
            // doing an animate verb ("Officially collapsing, the inbox demands
            // loyalty," / "Brain fizzing, the afternoon grinds," / "Sincerely
            // doomed, the calendar screams,"). The comma+definite-article is
            // the structural signature of that second personified clause. None
            // of the user-blessed unhinged lines contain ", the/a/an " after a
            // comma — they're single clauses or idioms — so this ban is
            // surgical: it kills the entire rut class and preserves every
            // vetted example. Verified 20/20 blessed lines pass, 9/10 rut
            // lines reject.
            if lowercased.contains(", the ") || lowercased.contains(", a ") || lowercased.contains(", an ") {
                return .invalid(reason: "Unhinged signoff uses a personified second clause (', the/a/an X …') — single clause only, no comma-chained noun personification")
            }
            // Reject the trailing "… in [noun]" prepositional-phrase ending.
            // This is THE persistent unhinged rut anchor across every collapse
            // round observed: "Passwords resting in pieces," → "Calendar
            // crashing in fragments," → "Officially drowning in spreadsheets,"
            // → "Permanently tangled in protocols," → "Officially frozen in
            // motivation,". Different grammatical wrappers, same ending slot.
            // The model latches onto "[state] in [noun]" as a generation
            // template and rotates the nouns. Verified: 18/20 rut lines end
            // this way, 0/20 user-blessed unhinged lines end this way — every
            // blessed line is a single clause or idiom that never trails into
            // "in [last-word]". Banning the ending kills the whole lineage
            // with zero collateral. (Prepositions mid-line like "With ongoing
            // regret," are untouched — only the trailing "in <word>" tail.)
            let inEndingRegex = try! NSRegularExpression(pattern: #"\bin \w+[,.]?$"#, options: [.caseInsensitive])
            let inEndingRange = NSRange(location: 0, length: lowercased.utf16.count)
            if inEndingRegex.firstMatch(in: lowercased, options: [], range: inEndingRange) != nil {
                return .invalid(reason: "Unhinged signoff ends with 'in [noun]' trailing prepositional phrase — a persistent template rut. Use a single clause or idiom, not '[state] in [noun]'.")
            }
        }

        // 12. Readability check - must have at least one vowel per word on average
        let vowelCount = lowercased.filter { "aeiou".contains($0) }.count
        if wordCount > 0 && vowelCount < wordCount {
            return .invalid(reason: "Poor readability (insufficient vowels)")
        }

        // 13. Coherence check — reject outputs that read as noun-collision
        // word salad. Long signoffs (4+ words) for general/unhinged must have
        // at least one function word (a, the, my, in, on, and, but, with, for,
        // to, of, is, am, being, etc.) connecting the nouns. A line like
        // "Zest, sleepy circuits," or "giggle bombs, yeah," has none → reject.
        if (bucketId == "standard" || bucketId == "unhinged") && wordCount >= 4 {
            let functionWords: Set<String> = [
                "a", "an", "the", "my", "your", "our", "his", "her", "their",
                "in", "on", "at", "and", "but", "with", "for", "to", "of", "is",
                "am", "being", "still", "again", "mostly", "really", "just",
                "not", "no", "only", "barely", "almost", "slightly", "very",
                "yet", "now", "here", "there", "before", "after", "if", "or",
                "this", "that", "it", "i", "you", "we", "they", "me", "us",
                "as", "do", "does", "maybe"
            ]
            let tokens = trimmed.lowercased()
                .split { $0.isWhitespace || $0 == "," || $0 == "." }
                .map { String($0) }
                .filter { !$0.isEmpty }
            let hasFunctionWord = tokens.contains { functionWords.contains($0) }
            if !hasFunctionWord {
                return .invalid(reason: "Incoherent — no function words linking the nouns (word salad)")
            }
        }

        // 14. Short-tier bare-noun salad — the gap rule-13 (4+ words only) misses.
        // The 3B's latent food/object fixation surfaces as bare 2-3-word noun
        // stacks ("Banana peel," / "Banana split," / "Umbrella down,") which
        // read as salad to a human but pass every regex gate above: not a banned
        // token, not a duplicate, not a template skeleton, short enough to dodge
        // rule-13's 4-word floor. Catch by SHAPE — a 2-3 word line whose tokens
        // are ALL concrete-noun-class (≥1 from concreteNounSet AND none a
        // function/verb/pronoun) is a bare-noun closer with no twist → reject.
        // Single-word closers ("Bazinga,") and 3-word function-bearing closers
        // ("Winter is coming,") are deliberately NOT caught (single-token or
        // has a function word). Noun set is gate-internal (never prompt-visible)
        // so it can enumerate banana without amplifying it.
        if (bucketId == "standard" || bucketId == "unhinged")
            && wordCount >= 2 && wordCount <= 3 {
            let tokensShort = trimmed.lowercased()
                .split { $0.isWhitespace || $0 == "," || $0 == "." }
                .map { String($0) }
                .filter { !$0.isEmpty }
            let functionWordsShort: Set<String> = [
                "a","an","the","my","your","our","his","her","their",
                "in","on","at","and","but","with","for","to","of","is","am",
                "being","not","no","only","barely","it","i","you","we","they",
                "me","us","as","do","does","maybe","like","than","so"
            ]
            let noneFunction = tokensShort.allSatisfy { !functionWordsShort.contains($0) }
            let hasConcreteNoun = tokensShort.contains { concreteNounSet.contains($0) }
            if noneFunction && hasConcreteNoun {
                return .invalid(reason: "Short bare-noun closer (food/object fixation) — no twist, reads as salad. Use a real phrase/idiom/catchphrase, not a bare noun.")
            }
        }

        // 15. Lead-concrete-noun-no-predication salad — the 4-7 word escapees
        // of rule-14. When rule-14 blocks 2-3 word bare-noun stacks, the 3B
        // ADAPTS by padding banana-salad with a function-word tail: "Banana
        // split on the moon," / "Banana peels on the keyboard," / "Banana in
        // the blender,". These have a function word (so rule-13's 4+ function-
        // word requirement is met) but are still noun-pile salad: a concrete noun
        // LEADS as subject AND there is no real predication (no copula like is/
        // are/was, no modal, no action verb from realVerbIndicators). A
        // verb-bearing noun-led line ("Winter is coming," has "is") passes; a
        // bare-noun-led line with only prepositions/articles has no predication
        // and reads as salad → reject. Noun set is gate-internal (never prompt-
        // visible). realVerbIndicators is modest; extend if new preposition-
        // padded salad surfaces.
        if (bucketId == "standard" || bucketId == "unhinged")
            && wordCount >= 4 && wordCount <= 7 {
            let tokensLead = trimmed.lowercased()
                .split { $0.isWhitespace || $0 == "," || $0 == "." }
                .map { String($0) }
                .filter { !$0.isEmpty }
            let realVerbIndicators: Set<String> = [
                "is","are","was","were","be","been","being","has","have","had",
                "falling","falls","hurts","hurt","comes","coming","sent","crafted",
                "signed","written","dictated","living","live","speak","spoken",
                "ride","arrived","stays","leaves","remains","looks","keeps","grows"
            ]
            let leadsConcrete = !tokensLead.isEmpty && concreteNounSet.contains(tokensLead[0])
            let hasRealVerb = tokensLead.contains { realVerbIndicators.contains($0) }
            if leadsConcrete && !hasRealVerb {
                return .invalid(reason: "Lead-noun salad (concrete noun leads, no predication) — reads as a noun pile, not a joke. Put the joke in a real sentence shape.")
            }
        }

        return .valid(trimmed)
    }

    // MARK: - Internal Helpers

    private func normalizeForComparison(_ text: String) -> String {
        return text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Opening-bigram skeleton: the first two tokens, for 3+ token lines.
    /// Catches a fixed-opening rut ("With thoughtful X,") where the model
    /// rotates the tail to clear word-similarity. Returns nil for short
    /// lines (handled by exact-duplicate).
    private func openingFingerprint(_ text: String) -> String? {
        let tokens = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard tokens.count >= 3 else { return nil }
        return "\(tokens[0]) \(tokens[1]) …"
    }

    /// Closing-tic skeleton: the LAST token, for 5+ token lines only. The
    /// model's melodramatic-suffix rut ("… groaned, barely," / "… rebelled,
    /// quietly,") tacks a single adverb onto the end of long lines; the
    /// open/last word rotates but the SAME closing adverb recurs 20×. We only
    /// fingerprint close-shape for long lines (5+) so that a legitimate final
    /// word on a short closer ("Best regards,") is NOT flagged as a tic —
    /// long lines ending in the same adverb genuinely are template-rotation.
    /// Returns nil for <5 token lines.
    private func closingFingerprint(_ text: String) -> String? {
        let tokens = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard tokens.count >= 5 else { return nil }
        return "… \(tokens.last!)"
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