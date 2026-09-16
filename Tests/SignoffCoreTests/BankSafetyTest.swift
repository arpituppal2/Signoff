import Testing
import Foundation
@testable import SignoffCore

/// Regression guard on the curated banks. The user's hard rules (2026-09-13,
/// take precedence over everything): no apologies, no self-deprecation, no
/// accusations / reader-directed negativity, and each line must FUNCTION as an
/// email closer. Banked lines are served verbatim as the final signoff, so a
/// rule-violating line would ship to a real recipient. Any future curation that
/// reintroduces one fails here.
@Suite struct BankSafetyTest {
    private static let buckets = [
        BucketID.standard.rawValue,
        BucketID.professional.rawValue,
        BucketID.unhinged.rawValue,
    ]

    @Test(arguments: buckets)
    func noApologyOpeners(bucket: String) async throws {
        let bank = try await bankLines(bucket)
        let bad = bank.filter { l in
            let n = normalize(l)
            return n.hasPrefix("sorry") || n.hasPrefix("apologies")
                || n.hasPrefix("my apologies") || n.hasPrefix("my bad")
        }
        #expect(bad.isEmpty, "[\(bucket)] apology openers: \(bad)")
    }

    @Test(arguments: buckets)
    func noSelfDeprecation(bucket: String) async throws {
        let bank = try await bankLines(bucket)
        // "I('m| am|'ve) (so|too|really|…|not|terrible|a mess|the worst|…)": the
        // same scaffold the live validator rejects. A banked line with a first-
        // person negative claim reads as a real admission when a recipient gets it.
        let re = #"\bi('m| am|'ve| will| won't)\s+(so|too|really|truly|honestly|basically|just|not|terrible|awful|bad|the worst|a mess|a disaster|incompetent|useless|hopeless|sorry)\b"#
        let bad = bank.filter { $0.range(of: re, options: .regularExpression) != nil }
        #expect(bad.isEmpty, "[\(bucket)] self-deprecating lines: \(bad)")
    }

    @Test(arguments: buckets)
    func noReaderDirectedNegativity(bucket: String) async throws {
        let bank = try await bankLines(bucket)
        // Lines that dismiss, insult, or refuse the reader — a real recipient
        // could take these the wrong way in a professional email.
        let re = #"(good luck with that|wouldn't wanna be ya|respectfully, no|unconvinced|no offense|don't @ me|whatever, man|get over it)"#
        let bad = bank.filter { $0.range(of: re, options: [.regularExpression, .caseInsensitive]) != nil }
        #expect(bad.isEmpty, "[\(bucket)] reader-directed-negative lines: \(bad)")
    }

    @Test(arguments: buckets)
    func linesEndWithComma(bucket: String) async throws {
        let bank = try await bankLines(bucket)
        // Signoff fragments are formatted with a trailing comma. A line ending in
        // a question mark or period is a full sentence, not a closer.
        let bad = bank.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(",") }
        #expect(bad.isEmpty, "[\(bucket)] lines not ending in comma: \(bad)")
    }

    @Test(arguments: buckets)
    func noUnresolvedPlaceholders(bucket: String) async throws {
        // PromptTemplate.load resolves dynamic tokens ({weekday}) per call, so a
        // literal placeholder reaching a banked line means the shipping path
        // would paste the raw token ("Not built for {weekday},") to a recipient.
        // ("I take tips, my Venmo is ____," uses a deliberate stylistic blank, not
        // template syntax, so only brace/bracket tokens are flagged.)
        let t = try await PromptTemplate.load(bucket: bucket) ?? .fallback
        let bad = t.positiveExamples.filter { $0.contains("{") || $0.contains("[") }
        #expect(bad.isEmpty, "[\(bucket)] unresolved placeholders: \(bad)")
    }

    private func bankLines(_ bucket: String) async throws -> [String] {
        let t = try await PromptTemplate.load(bucket: bucket) ?? .fallback
        return t.positiveExamples
            .map { ProviderResponseGuard.sanitizeSignoff($0) }
            .filter { !$0.isEmpty }
    }

    private func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}