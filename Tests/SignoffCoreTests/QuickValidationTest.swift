import Testing
import Foundation
@testable import SignoffCore

@MainActor
struct QuickValidationTest {
    // User‑provided S‑tier examples (each line ends with a comma).
    private let sTierExamples = """
All fax, no printer,
Please hesitate to reach out,
Sent from my last 3.5 brain cells,
No cheers, only tears,
With queso on top,
Alright, alright, alright,
Thanking you, dearest one,
Not build for [day of the week, dynamic],
I have spoken,
We ride at dawn,
Sent from my pillow fort,
Sent while contemplating waffles,
You just lost The Game,
Keep climbing your mountains,
Not sent from my fridge,
Sent with the poison, the poison for Kuzco,
No espresso, all depresso,
Foaming at the mouth,
From the pits of hell,
Putting the "fun" in dysfunctional,
I take tips, my venmo is ______,
Brought to you by a bit too much caffeine,
lock in.
"""

    @Test("Generate 1 raw signoff per bucket (using generateRaw) and validate")
    func generate1RawValidation() async throws {
        try requireLiveTestsEnabled()
        // Own instance — Swift Testing runs tests in parallel and the shared
        // singleton's inflightRequest guard rejects concurrent callers.
        let service = GenerationService()
        // Warm up
        print("Warming up Foundation Models...")
        await service.warmup()

        let buckets = ["standard", "professional", "unhinged"]

        for bucket in buckets {
            print("\n\n=== PROCESSING BUCKET: \(bucket) ===")

            let outcome = await service.generateRaw(
                bucketId: bucket,
                profile: nil,
                recentTexts: [],
                toneValue: nil,
                postfixMode: .nothing,
                customInstructions: sTierExamples,
                phraseList: nil,
                ageGroup: .genZ,
                preferredRegister: nil
            )

            switch outcome {
            case .success(let outcome):
                let text = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
                print("Generated: '\(text)'")

                // Validate: word count 2-7, ends with exactly one comma, clean terminus
                let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                let wordCount = words.count
                #expect(wordCount >= 2 && wordCount <= 7, "Word count \(wordCount) not in 2-7 for bucket \(bucket)")

                let commaCount = text.filter { $0 == "," }.count
                #expect(commaCount == 1, "Expected exactly one comma, got \(commaCount) in bucket \(bucket)")

                #expect(text.hasSuffix(","), "Does not end with comma in bucket \(bucket)")

                // Clean terminus (already ends with comma, but check)
                guard let last = text.last else { Issue.record("Empty string"); return }
                #expect(last == "," || last == "." || last.isLetter, "Failed terminus check in bucket \(bucket)")

                print("   ✅ PASSES validation")
            case .providerFailed(let reason):
                print("\(String(format: "%2d", 0)): Provider failed: \(reason)")
                Issue.record("Provider failed: \(reason)")
            case .usageLimitReached:
                print("\(String(format: "%2d", 0)): Usage limit reached")
                Issue.record("Usage limit reached")
            }
        }
    }

    @Test("Generate 1 raw signoff per bucket (using generateRaw) WITHOUT custom instructions")
    func generate1RawValidationNoCustom() async throws {
        try requireLiveTestsEnabled()
        let service = GenerationService()
        // Warm up
        print("Warming up Foundation Models...")
        await service.warmup()

        let buckets = ["standard", "professional", "unhinged"]

        for bucket in buckets {
            print("\n\n=== PROCESSING BUCKET: \(bucket) (no custom) ===")

            let outcome = await service.generateRaw(
                bucketId: bucket,
                profile: nil,
                recentTexts: [],
                toneValue: nil,
                postfixMode: .nothing,
                customInstructions: nil,
                phraseList: nil,
                ageGroup: .genZ,
                preferredRegister: nil
            )

            switch outcome {
            case .success(let outcome):
                let text = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
                print("Generated: '\(text)'")

                // Validate: word count 2-7, ends with exactly one comma, clean terminus
                let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                let wordCount = words.count
                #expect(wordCount >= 2 && wordCount <= 7, "Word count \(wordCount) not in 2-7 for bucket \(bucket)")

                let commaCount = text.filter { $0 == "," }.count
                #expect(commaCount == 1, "Expected exactly one comma, got \(commaCount) in bucket \(bucket)")

                #expect(text.hasSuffix(","), "Does not end with comma in bucket \(bucket)")

                // Clean terminus (already ends with comma, but check)
                guard let last = text.last else { Issue.record("Empty string"); return }
                #expect(last == "," || last == "." || last.isLetter, "Failed terminus check in bucket \(bucket)")

                print("   ✅ PASSES validation")
            case .providerFailed(let reason):
                print("\(String(format: "%2d", 0)): Provider failed: \(reason)")
                Issue.record("Provider failed: \(reason)")
            case .usageLimitReached:
                print("\(String(format: "%2d", 0)): Usage limit reached")
                Issue.record("Usage limit reached")
            }
        }
    }

    private func requireLiveTestsEnabled() throws {
        guard ProcessInfo.processInfo.environment["SIGNOFF_RUN_LIVE_TESTS"] == "1" else {
            throw NSError(domain: "SignoffLiveTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Set SIGNOFF_RUN_LIVE_TESTS=1 to run live Foundation Models tests."])
        }
    }

    private func hasCleanTerminus(_ s: String) -> Bool {
        guard let last = s.last else { return false }
        return last == "," || last == "." || last.isLetter
    }
}
