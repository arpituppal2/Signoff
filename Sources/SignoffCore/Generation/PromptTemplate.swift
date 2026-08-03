import Foundation

public struct PromptTemplate: Codable, Sendable, Equatable {
    public let system: String
    public let userVariants: [UserVariant]
    public let positiveExamples: [String]
    // New: emotional registers for the new prompt style
    public let registers: [Register]?

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

    public struct Register: Codable, Sendable, Equatable {
        public let name: String
        public let cue: String
        public let examples: [String]

        public init(name: String, cue: String, examples: [String]) {
            self.name = name
            self.cue = cue
            self.examples = examples
        }
    }

    public init(system: String,
                userVariants: [UserVariant],
                positiveExamples: [String],
                registers: [Register]? = nil) {
        self.system = system
        self.userVariants = userVariants
        self.positiveExamples = positiveExamples
        self.registers = registers
    }
}

public extension PromptTemplate {
    /// Loads `Resources/Prompts/<bucket>.json`. Maps `standard` → `general`
    /// so the legacy resource name stays valid.
    static func load(bucket: String) async -> PromptTemplate? {
        guard !bucket.isEmpty else { return nil }
        let resource = (bucket == BucketID.standard.rawValue) ? "general" : bucket

        // Static cache to avoid repeated JSON parsing
        if let cached = await PromptTemplateCache.shared.get(resource) {
            return cached
        }

        guard let url = Bundle.module.url(
            forResource: resource,
            withExtension: "json",
            subdirectory: "Prompts"
        ) else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        do {
            let decoded = try JSONDecoder().decode(PromptTemplate.self, from: data)
            await PromptTemplateCache.shared.set(resource, decoded)
            return decoded
        } catch {
            return nil
        }
    }

    static let fallback = PromptTemplate(
        system: "You write short, natural email signoffs. Output only the signoff phrase.",
        userVariants: [
            .init(when: .init(), user: "Write a single-sentence signoff that fits an editorial email.")
        ],
        positiveExamples: ["Thanks, this looks great.", "Talk soon."]
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

// MARK: - Internal Cache

private actor PromptTemplateCache {
    static let shared = PromptTemplateCache()
    private var storage: [String: PromptTemplate] = [:]
    private init() {}

    func get(_ key: String) async -> PromptTemplate? {
        storage[key]
    }

    func set(_ key: String, _ value: PromptTemplate) async {
        storage[key] = value
    }
}
