import Testing
import Foundation
@testable import SignoffCore

struct BankQualityTests {

    /// Scans a bucket's curated bank (the phrases served via QuoteSelector) for
    /// the noun-salad scaffolds the on-device 3B used to produce. A bank line is
    /// only acceptable if it is a real, complete, fixed phrase.
    private func saladScaffolds(_ text: String) -> Bool {
        let lower = text.lowercased()
        let banned: [String] = [
            "signed from a ",       // "[past participle] from a [object]"
            "emailed by a ",
            "powered by a ",
            "dispatched by a ",
            "created by a ",
            "signed by a ",
            " an AI",               // meta, reads as machine-broken
            " as a service",        // tech-joke scaffold, not a closer
            "that got ghosted",
            "that just got ",
            "my last 3.5 brain cells said", // model paraphrase of user's line
        ]
        return banned.contains { lower.contains($0) }
    }

    @Test("Unhinged bank parses with all real, distinct, non-salad lines")
    func unhingedBankQuality() async {
        let template = await PromptTemplate.load(bucket: "unhinged")
        let lines = template?.positiveExamples.map {
            ProviderResponseGuard.sanitizeSignoff($0)
        } ?? []
        #expect(!lines.isEmpty, "unhinged bank must not be empty")
        #expect(Set(lines).count == lines.count, "unhinged bank has duplicate lines")
        for line in lines {
            #expect(!line.isEmpty)
            #expect(!saladScaffolds(line), "unhinged bank contains a noun-salad scaffold: \(line)")
        }
    }

    @Test("Standard bank parses with all real, distinct, non-salad lines")
    func standardBankQuality() async {
        let template = await PromptTemplate.load(bucket: "standard")
        let lines = template?.positiveExamples.map {
            ProviderResponseGuard.sanitizeSignoff($0)
        } ?? []
        #expect(!lines.isEmpty, "standard bank must not be empty")
        #expect(Set(lines).count == lines.count, "standard bank has duplicate lines")
        for line in lines {
            #expect(!line.isEmpty)
            #expect(!saladScaffolds(line), "standard bank contains a noun-salad scaffold: \(line)")
        }
    }
}