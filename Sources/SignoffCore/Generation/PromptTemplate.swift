import Foundation

public struct PromptTemplate: Codable, Sendable, Equatable {
    public let system: String
    public let rules: [String]
    public let userVariants: [UserVariant]
    public let guardWords: [String]
    public let positiveExamples: [String]
    public let negativeExamples: [String]

    public struct UserVariant: Codable, Sendable, Equatable {
        public let when: When
        public let user: String

        public struct When: Codable, Sendable, Equatable {
            public let unhingedLevel: String?
            /// Codable stand-in for `ClosedRange<Double>` (JSON object with lower/upper).
            public let toneRange: ToneRange?
            public let postfixMode: String?

            public init(unhingedLevel: String? = nil,
                        toneRange: ToneRange? = nil,
                        postfixMode: String? = nil) {
                self.unhingedLevel = unhingedLevel
                self.toneRange = toneRange
                self.postfixMode = postfixMode
            }
        }

        public init(when: When, user: String) {
            self.when = when
            self.user = user
        }
    }

    public struct ToneRange: Codable, Sendable, Equatable {
        public let lower: Double
        public let upper: Double

        public init(lower: Double, upper: Double) {
            self.lower = lower
            self.upper = upper
        }

        public var closed: ClosedRange<Double> { lower...upper }
    }

    public init(system: String,
                rules: [String],
                userVariants: [UserVariant],
                guardWords: [String],
                positiveExamples: [String],
                negativeExamples: [String]) {
        self.system = system
        self.rules = rules
        self.userVariants = userVariants
        self.guardWords = guardWords
        self.positiveExamples = positiveExamples
        self.negativeExamples = negativeExamples
    }
}

public extension PromptTemplate {
    /// Loads `Resources/Prompts/<bucket>.json`. Maps `standard` → `general`
    /// so the legacy resource name stays valid.
    static func load(bucket: String) -> PromptTemplate? {
        guard !bucket.isEmpty else { return nil }
        let resource = (bucket == BucketID.standard.rawValue) ? "general" : bucket
        guard let url = Bundle.module.url(
            forResource: resource,
            withExtension: "json",
            subdirectory: "Prompts"
        ) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PromptTemplate.self, from: data)
    }

    static let fallback = PromptTemplate(
        system: "You write short, natural email signoffs. Output only the signoff phrase.",
        rules: [
            "Never include the recipient or sender name.",
            "Never start with 'I'.",
            "Keep it to one sentence, 3–14 words.",
            "End with a period, exclamation, or question mark.",
        ],
        userVariants: [
            .init(when: .init(), user: "Write a single-sentence signoff that fits an editorial email.")
        ],
        guardWords: ["maybe", "perhaps", "just", "kindly"],
        positiveExamples: ["Thanks, this looks great.", "Talk soon."],
        negativeExamples: ["OK.", "Let me know if you have any questions, please."]
    )

    func chooseUser(unhingedLevel: UnhingedLevel? = nil,
                    toneValue: Double? = nil,
                    postfixMode: BucketPostfixMode? = nil) -> String {
        let matching = userVariants.filter { v in
            if let u = v.when.unhingedLevel, u != unhingedLevel?.rawValue { return false }
            if let range = v.when.toneRange, let tv = toneValue, !range.closed.contains(tv) { return false }
            if let p = v.when.postfixMode, p != postfixMode?.rawValue { return false }
            return true
        }
        return matching.first?.user
            ?? "Write a single-sentence signoff that fits an editorial email."
    }
}
