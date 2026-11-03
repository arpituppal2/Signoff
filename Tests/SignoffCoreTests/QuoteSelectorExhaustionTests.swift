import Testing
import Foundation
@testable import SignoffCore

struct QuoteSelectorExhaustionTests {

    @Test("selector rotates through the whole bank before repeating")
    func rotatesThroughBankBeforeRepeating() {
        let bank = (1...10).map { "Phrase \($0)," }
        let template = PromptTemplate(system: "quotes", userVariants: [], positiveExamples: bank)

        var recent: [String] = []
        var seen: Set<String> = []
        var repeatsBeforeFullCycle = 0
        for _ in 0..<10 {
            guard let pick = QuoteSelector.select(from: template, avoiding: recent) else {
                Issue.record("selector returned nil with an unused bank")
                return
            }
            if seen.contains(pick) { repeatsBeforeFullCycle += 1 }
            seen.insert(pick)
            recent.append(pick)
        }
        // A full cycle of 10 unique uses must not repeat anything.
        #expect(repeatsBeforeFullCycle == 0)
        #expect(seen.count == 10)
    }

    @Test("selector does not lock onto one line when the bank is exhausted")
    func doesNotLockWhenExhausted() {
        let bank = ["Alpha,", "Beta,", "Gamma,", "Delta,", "Epsilon,"]
        let template = PromptTemplate(system: "quotes", userVariants: [], positiveExamples: bank)

        // Exhaust the bank and then drive well past it with a capped-size history.
        var recent = bank
        var distinct: Set<String> = []
        for _ in 0..<30 {
            guard let pick = QuoteSelector.select(from: template, avoiding: recent) else {
                Issue.record("selector returned nil")
                return
            }
            distinct.insert(pick)
            // Cap history like the service does, re-appending each pick.
            recent.removeAll { $0 == pick }
            recent.append(pick)
        }
        // LRU selection must keep visiting every line even when history is capped.
        #expect(distinct.count == bank.count)
    }

    @Test("selector prefers never-seen lines before any repeat")
    func prefersFreshLines() {
        let template = PromptTemplate(
            system: "quotes", userVariants: [],
            positiveExamples: ["Alpha,", "Beta,", "Gamma,"])
        // All except Beta have been used.
        let pick = QuoteSelector.select(from: template, avoiding: ["Alpha,", "Gamma,"])
        #expect(pick == "Beta,")
    }
}