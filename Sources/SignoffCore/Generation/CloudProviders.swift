import Foundation

/// Cloud generation providers (OpenAI + Anthropic).
///
/// Design notes:
/// - These exist to replace the on-device 3B Foundation Models model as the
///   PRIMARY generation path (see docs/CLOUD_PLAN.md). The 3B model remains
///   the offline fallback only.
/// - Keys resolve from the environment first (`SIGNOFF_OPENAI_KEY` /
///   `SIGNOFF_ANTHROPIC_KEY` — used by the bench harness and CI), then from
///   the Keychain (`com.signoff` service, accounts `api.openai` /
///   `api.anthropic`).
/// - Validation here is intentionally MINIMAL: format sanitize + pasteable +
///   length + per-bucket safety. The banned-word graveyard, mechanism lanes,
///   and 24-attempt retry scaffolding in Providers.swift are 3B-era
///   compensations; frontier-class models do not need them and the user has
///   explicitly rejected hardcoded compensations.
/// - Rolling-history avoid lists are injected by the caller (see
///   PromptComposer's professional block; bench/cloud-primary paths append
///   recent lines to the prompt tail). Cloud models handle avoid lists fine —
///   the "pink-elephant" limitation is a 3B-only failure mode.

/// Shared config for cloud providers. Model IDs live here so they can be
/// swapped without touching call sites.
public enum CloudProviderConfig {
    public static let openAIModel = "gpt-4o-mini"
    public static let anthropicModel = "claude-haiku-4-5"
    /// Spec budget: cloud calls must fail fast; FM fallback can serve offline.
    public static let timeoutSeconds: TimeInterval = 5
    public static let maxTokens = 96
}

// MARK: - Key resolution

public enum CloudKeyStore {
    public static func openAIKey() throws -> String { try key(env: "SIGNOFF_OPENAI_KEY", account: "api.openai", provider: "OpenAI") }
    public static func anthropicKey() throws -> String { try key(env: "SIGNOFF_ANTHROPIC_KEY", account: "api.anthropic", provider: "Anthropic") }

    private static func key(env: String, account: String, provider: String) throws -> String {
        if let envValue = ProcessInfo.processInfo.environment[env], !envValue.isEmpty {
            return envValue
        }
        if let stored = try KeychainStore.shared.loadString(account: account), !stored.isEmpty {
            return stored
        }
        throw GenerationError.unavailable(reason: "No \(provider) API key configured (env \(env) or Keychain)")
    }
}

// MARK: - Error surfacing

// Human-readable reasons everywhere (bench output, status lines, logs).
extension GenerationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unavailable(let r): return "Unavailable: \(r)"
        case .timeout: return "Timed out"
        case .unsafeCandidate(let r): return "Unsafe candidate: \(r)"
        case .quotaBlocked(let r): return "Quota: \(r)"
        case .refused(let r): return "Refused: \(r)"
        case .guardrailViolation(let r): return "Guardrail: \(r)"
        case .contextWindowExceeded: return "Context window exceeded"
        case .providerFailed(let r): return r
        }
    }
}

// MARK: - Cloud provider walk (shipping path)

/// The cloud-primary walk used by GenerationService: available providers in
/// priority order (OpenAI first — cheapest — then Anthropic). An empty list
/// means no keys are configured and the FM fallback serves instead.
public enum CloudProviderWalk {
    public static func availableProviders() -> [any GenerationProvider] {
        var out: [any GenerationProvider] = []
        if (try? CloudKeyStore.openAIKey()) != nil { out.append(OpenAIProvider()) }
        if (try? CloudKeyStore.anthropicKey()) != nil { out.append(AnthropicProvider()) }
        return out
    }

    public static var hasAny: Bool { !availableProviders().isEmpty }
}

/// Cloud-model prompt augmentation. The static PromptComposer deliberately
/// keeps recent outputs out of creative-bucket prompts because the 3B model
/// copies what it is told to avoid ("pink elephant"). Cloud models handle
/// avoid lists fine — rolling history is exactly how a 50-emails-a-day user
/// stays repetition-free, so the shipping cloud path appends it here.
public enum CloudPromptAugment {
    public static func apply(_ composed: PromptComposer.Composed,
                             bucketId: String,
                             recentTexts: [String]) -> PromptComposer.Composed {
        // Professional already gets a recent-closers avoid block from
        // PromptComposer (closed vocabulary — safe to name there).
        guard bucketId != BucketID.professional.rawValue, !recentTexts.isEmpty else {
            return composed
        }
        let window = recentTexts.suffix(30).map { "- \($0)" }.joined(separator: "\n")
        return PromptComposer.Composed(
            instructions: composed.instructions,
            prompt: composed.prompt
                + "\n\nRecent lines you already produced for this user — do NOT repeat them or trivial variants:\n"
                + window,
            promptPrefix: composed.promptPrefix)
    }
}

// MARK: - OpenAI

@available(macOS 26, *)
public struct OpenAIProvider: GenerationProvider {
    public let name = "OpenAI (\(CloudProviderConfig.openAIModel))"
    public let kindRaw = GenerationProviderKind.openAI.rawValue

    public init() {}

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = CloudProviderConfig.timeoutSeconds
        config.timeoutIntervalForResource = CloudProviderConfig.timeoutSeconds + 3
        return URLSession(configuration: config)
    }()

    public func generate(_ context: ProviderGenerateContext) async throws -> String {
        let key = try CloudKeyStore.openAIKey()

        struct RequestBody: Encodable {
            let model: String
            let messages: [Message]
            let temperature: Double
            let max_tokens: Int
            struct Message: Encodable {
                let role: String
                let content: String
            }
        }
        struct ResponseBody: Decodable {
            struct Choice: Decodable {
                struct Msg: Decodable { let content: String? }
                let message: Msg?
            }
            let choices: [Choice]?
            struct APIError: Decodable { let message: String? }
            let error: APIError?
        }

        let body = RequestBody(
            model: CloudProviderConfig.openAIModel,
            messages: [
                .init(role: "system", content: context.composed.instructions),
                .init(role: "user", content: context.composed.prompt),
            ],
            temperature: ProviderResponseGuard.temperature(for: context),
            max_tokens: CloudProviderConfig.maxTokens)

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await Self.session.data(for: request)
        try Self.throwForHTTPStatus(response, data: data, provider: "OpenAI")

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        let text = decoded.choices?.first?.message?.content ?? ""
        return try Self.validate(text, bucketId: context.bucketId)
    }

    /// Shared light validation for both cloud providers. One retry on an
    /// empty/guarded response, then throw — the caller owns retries.
    static func validate(_ text: String, bucketId: String) throws -> String {
        let sanitized = ProviderResponseGuard.sanitizeSignoff(text, bucketId: bucketId)
        let pasteable = try ProviderResponseGuard.validatedPasteable(sanitized, provider: "cloud")
        let lengthChecked = try ProviderResponseGuard.validatedLength(pasteable)
        if bucketId == BucketID.unhinged.rawValue {
            return try ProviderResponseGuard.validatedCynical(lengthChecked)
        }
        return lengthChecked
    }

    static func throwForHTTPStatus(_ response: URLResponse, data: Data, provider: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GenerationError.providerFailed(reason: "\(provider): no HTTP response")
        }
        guard !(200...299).contains(http.statusCode) else { return }
        let snippet = String(data: data.prefix(300), encoding: .utf8) ?? ""
        switch http.statusCode {
        case 401, 403:
            throw GenerationError.providerFailed(reason: "\(provider): invalid or unauthorized API key (401/403)")
        case 429:
            throw GenerationError.providerFailed(reason: "\(provider): rate limited (429)")
        case 408, 504:
            throw GenerationError.timeout
        default:
            throw GenerationError.providerFailed(reason: "\(provider): HTTP \(http.statusCode) \(snippet)")
        }
    }
}

// MARK: - Anthropic

@available(macOS 26, *)
public struct AnthropicProvider: GenerationProvider {
    public let name = "Anthropic (\(CloudProviderConfig.anthropicModel))"
    public let kindRaw = GenerationProviderKind.anthropic.rawValue

    public init() {}

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = CloudProviderConfig.timeoutSeconds
        config.timeoutIntervalForResource = CloudProviderConfig.timeoutSeconds + 3
        return URLSession(configuration: config)
    }()

    public func generate(_ context: ProviderGenerateContext) async throws -> String {
        let key = try CloudKeyStore.anthropicKey()

        struct RequestBody: Encodable {
            let model: String
            let max_tokens: Int
            let temperature: Double
            let system: String
            let messages: [Message]
            struct Message: Encodable {
                let role: String
                let content: String
            }
        }
        struct ResponseBody: Decodable {
            struct Block: Decodable {
                let type: String?
                let text: String?
            }
            struct APIError: Decodable { let message: String? }
            let content: [Block]?
            let error: APIError?
        }

        let body = RequestBody(
            model: CloudProviderConfig.anthropicModel,
            max_tokens: CloudProviderConfig.maxTokens,
            temperature: ProviderResponseGuard.temperature(for: context),
            system: context.composed.instructions,
            messages: [.init(role: "user", content: context.composed.prompt)])

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await Self.session.data(for: request)
        try OpenAIProvider.throwForHTTPStatus(response, data: data, provider: "Anthropic")

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        let text = (decoded.content ?? [])
            .filter { $0.type == nil || $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: " ")
        return try OpenAIProvider.validate(text, bucketId: context.bucketId)
    }
}
