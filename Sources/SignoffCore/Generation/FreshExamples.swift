import Foundation

/// Fresh few-shot examples, harvested from the web.
///
/// Purpose (user decision 2026-08-27): the static example banks in
/// `Prompts/*.json` anchor generation — a model that sees the same "pillow
/// fort / waffles" examples produces the same riffs. This service fetches
/// REAL signoff-shaped lines from the web on a rolling basis, caches a small
/// pool, and the caller injects them as additional style anchors
/// (`PromptComposer.compose(curatedExamples:)`).
///
/// Hard design rule (user's): this is NOT a serving corpus. The pool is a
/// handful of style anchors for the model to riff on; users never get a line
/// straight from the pool, so no exhaustion-within-2-weeks failure mode
/// exists. Static prompt banks remain the offline fallback.
///
/// Search provider: Exa (semantic search with built-in text extraction —
/// returns page text, not just links). Key: env `EXA_API_KEY` or Keychain
/// account `api.exa`. Swap via `SearchClient` if needed.

// MARK: - Search abstraction

public struct SearchResult: Sendable {
    public let title: String
    public let url: String
    public let text: String

    public init(title: String, url: String, text: String) {
        self.title = title
        self.url = url
        self.text = text
    }
}

public protocol SearchClient: Sendable {
    func search(query: String, maxResults: Int) async throws -> [SearchResult]
}

/// Exa /search client. Semantic search + `contents.text` extraction.
public struct ExaSearchClient: SearchClient {
    public init() {}

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    public func search(query: String, maxResults: Int) async throws -> [SearchResult] {
        let key = try FreshExamplesService.key()
        var request = URLRequest(url: URL(string: "https://api.exa.ai/search")!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Body: Encodable {
            let query: String
            let numResults: Int
            let contents: Contents
            struct Contents: Encodable {
                let text: TextOpts
                struct TextOpts: Encodable { let maxCharacters: Int }
            }
        }
        struct Response: Decodable {
            struct Item: Decodable {
                let title: String?
                let url: String?
                let text: String?
            }
            let results: [Item]?
        }

        request.httpBody = try JSONEncoder().encode(
            Body(query: query, numResults: maxResults,
                 contents: .init(text: .init(maxCharacters: 2000))))

        let (data, response) = try await Self.session.data(for: request)
        try OpenAIProvider.throwForHTTPStatus(response, data: data, provider: "Exa")
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.results ?? []).map {
            SearchResult(title: $0.title ?? "", url: $0.url ?? "", text: $0.text ?? "")
        }
    }
}

// MARK: - Candidate filtering (pure, unit-testable)

public enum FreshExamplesFilter {
    /// Meta-discussion words that mark a line as ABOUT signoffs, not one.
    static let metaWords = ["sign-off", "signoff", "signature", "email", "e-mail",
                            "reddit", "upvote", "comment", "thread", "http",
                            "www.", ".com", ".net", "@", "list of", "examples of"]
    /// Unsafe/mean patterns reused from the unhinged safety gate.
    static let safety = ProviderResponseGuard.self

    /// Pull signoff-shaped candidate lines out of arbitrary page text.
    public static func candidateLines(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .flatMap { $0.split(whereSeparator: { ".!?;".contains($0) }) }
            .map { line in
                var l = line.trimmingCharacters(in: .whitespaces)
                // Strip bullets/numbering/quotes.
                while let f = l.first, "-•*#>\"'0123456789. ".contains(f) { l.removeFirst() }
                while let last = l.last, "\"'.!? ".contains(last) { l.removeLast() }
                return l.trimmingCharacters(in: .whitespaces)
            }
    }

    /// Shape + safety + dedupe filter. Returns lines formatted as signoffs
    /// (trailing comma, capitalized first word).
    public static func filter(_ lines: [String], existing: Set<String>, maxCount: Int = 8) -> [String] {
        var seen = Set(existing.map { $0.lowercased() })
        var out: [String] = []

        for raw in lines {
            guard !raw.isEmpty else { continue }
            let lower = raw.lowercased()
            guard !metaWords.contains(where: { lower.contains($0) }) else { continue }
            guard raw.range(of: #"[0-9]{3,}"#, options: .regularExpression) == nil else { continue }
            // Emoji-heavy lines rarely survive as signoffs; drop them here.
            guard raw.unicodeScalars.allSatisfy({ $0.value < 0x1F000 || $0.properties.isEmojiPresentation == false }) else { continue }

            let words = raw.split { $0.isWhitespace }.count
            guard (2...9).contains(words) else { continue }
            guard let first = raw.first, first.isLetter, first.isUppercase else { continue }

            // Safety gate (same class as the unhinged shipping gate).
            guard (try? safety.validatedCynical(raw)) != nil else { continue }

            // Try to score; lines failing safety are skipped silently.
            let formatted = raw.hasSuffix(",") ? raw : raw + ","
            let key = formatted.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(formatted)
            if out.count >= maxCount { break }
        }
        // Prefer compact lines first (signoff sweet spot).
        return out.sorted { ($0.split { $0.isWhitespace }.count, $0) < ($1.split { $0.isWhitespace }.count, $1) }
    }
}

// MARK: - Service

public final class FreshExamplesService: @unchecked Sendable {
    public static let shared = FreshExamplesService()

    /// Rotation cadence: a fresh pool weekly is plenty — anchors churn slowly
    /// by design so the model's output register stays coherent.
    static let ttl: TimeInterval = 7 * 24 * 3600
    static let poolSize = 8       // stored
    static let surfaceCount = 5   // injected per generation
    static let queryBank = [
        "funny email sign-offs and signatures people actually use",
        "hilarious ways to end an email",
        "absurd email closing lines people use",
        "funniest out of office message endings",
        "unhinged funny email sign off examples blog",
    ]

    private let cache: FreshExamplesCache
    private let client: any SearchClient

    public init(client: any SearchClient = ExaSearchClient(), cacheDirectory: URL? = nil) {
        self.client = client
        self.cache = FreshExamplesCache(directory: cacheDirectory)
    }

    /// Key resolution shared by the bench and (later) the proxy.
    static func key() throws -> String {
        if let env = ProcessInfo.processInfo.environment["EXA_API_KEY"], !env.isEmpty {
            return env
        }
        if let stored = try KeychainStore.shared.loadString(account: "api.exa"), !stored.isEmpty {
            return stored
        }
        throw GenerationError.unavailable(reason: "No Exa API key configured (env EXA_API_KEY or Keychain api.exa)")
    }

    /// Cached-first examples; refreshes in the background when stale.
    /// Never throws: offline / no-key callers just get the stale pool or [].
    public func currentExamples(forceRefresh: Bool = false) async -> [String] {
        if !forceRefresh, let cached = await cache.loadIfFresh(maxAge: Self.ttl) {
            return Array(cached.prefix(Self.surfaceCount))
        }
        await refresh()
        let pool = await cache.pool()
        return Array(pool.prefix(Self.surfaceCount))
    }

    /// Search → extract → filter → persist. Best effort.
    @discardableResult
    public func refresh(now: Date = Date()) async -> [String] {
        let existing = await cache.pool()
        var candidates: [String] = []
        // Two rotated queries per refresh keeps results varied without burning quota.
        let queries = Self.queryBank.shuffled().prefix(2)
        for query in queries {
            do {
                let results = try await client.search(query: query, maxResults: 6)
                for r in results { candidates.append(contentsOf: FreshExamplesFilter.candidateLines(from: r.text)) }
            } catch {
                await GenerationDebugProbe.shared.recordEvent("fresh-examples search failed: \(error.localizedDescription)")
            }
        }
        let filtered = FreshExamplesFilter.filter(candidates, existing: Set(existing), maxCount: Self.poolSize)
        if !filtered.isEmpty {
            await cache.store(filtered, at: now)
        }
        return filtered
    }
}

// MARK: - Disk-backed cache

/// Actor-owned pool persisted to Application Support. Keeps the API surface
/// Sendable-clean under Swift 6 strict concurrency.
actor FreshExamplesCache {
    struct Snapshot: Codable {
        let fetchedAt: Date
        let examples: [String]
    }

    private let fileURL: URL
    private var snapshot: Snapshot?

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Signoff", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("FreshExamples.json")
    }

    func pool() -> [String] {
        ensureLoaded()
        return snapshot?.examples ?? []
    }

    func loadIfFresh(maxAge: TimeInterval) -> [String]? {
        ensureLoaded()
        guard let snap = snapshot else { return nil }
        guard Date().timeIntervalSince(snap.fetchedAt) < maxAge else { return nil }
        return snap.examples
    }

    func store(_ examples: [String], at date: Date) {
        let snap = Snapshot(fetchedAt: date, examples: examples)
        snapshot = snap
        if let data = try? JSONEncoder.signed.encode(snap) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func ensureLoaded() {
        guard snapshot == nil else { return }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder.signed.decode(Snapshot.self, from: data) else { return }
        snapshot = decoded
    }
}
