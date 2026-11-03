import Testing
import Foundation
@testable import SignoffCore

/// Test generation quality with S-tier examples as custom instructions - ensures we can generate valid signoffs
@MainActor
@Suite(.serialized)
struct SizesTierQualityTests {

    private let service = GenerationService.shared
    private let buckets = ["standard", "professional", "unhinged"]

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

    /// A signoff is a single clean line. Its terminus may be a comma (the
    /// conventional closer: "Best regards,"), a period (a punchy finished
    /// fragment: "Not built for Mondays."), or a bare letter (a fragment that
    /// needs no terminal: "Please hesitate to reach out"). Exclamation marks,
    /// emoji, and repeat punctuation are NOT acceptable for this app's voice.
    private func hasCleanTerminus(_ s: String) -> Bool {
        guard let last = s.last else { return false }
        return last == "," || last == "." || last.isLetter
    }

    /// Regression guard: Apple Foundation Models has an observed tendency to
    /// fixate on "banana" (and other single nouns) when generation drifts.
    /// Pass = none of the results mention it AND the bucket produced at least
    /// two distinct signoffs (no degenerate repeat-collapse).
    private func bananaSentinel(_ results: [String]) -> Bool {
        let lower = results.map { $0.lowercased() }
        if lower.contains(where: { $0.contains("banana") }) { return false }
        if Set(results).count < 2 { return false }
        return true
    }

    private func validateSignoffStrict(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Check word count (2-7 words)
        let words = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let wordCount = words.count
        guard wordCount >= 2 && wordCount <= 7 else {
            return false
        }
        // Check ends with exactly one comma
        guard trimmed.hasSuffix(",") else {
            return false
        }
        // Ensure only one comma (at the end)
        let commaCount = trimmed.filter { $0 == "," }.count
        guard commaCount == 1 else {
            return false
        }
        // Check terminus (though already ends with comma, but keep for consistency)
        guard let last = trimmed.last, last == "," || last == "." || last.isLetter else {
            return false
        }
        // Check first word capitalized
        guard let first = words.first, let firstChar = first.first, firstChar.isUppercase else {
            return false
        }
        // Check for banned words
        let banned = ["coffee", "drink", "beer", "wine", "whiskey"]
        let lower = trimmed.lowercased()
        guard !banned.contains(where: { lower.contains($0) }) else {
            return false
        }
        // Check for similes (X like Y pattern)
        guard trimmed.range(of: " like ", options: .caseInsensitive) == nil else {
            return false
        }
        return true
    }

    // Warm up model and invalidate session pool
    private func requireLiveTestsEnabled() throws {
        guard ProcessInfo.processInfo.environment["SIGNOFF_RUN_LIVE_TESTS"] == "1" else {
            throw NSError(domain: "SignoffLiveTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Set SIGNOFF_RUN_LIVE_TESTS=1 to run live Foundation Models tests."])
        }
    }

    private func warmup() async {
        print("[TEST] FoundationModelsAvailability.probe(): \(FoundationModelsAvailability.probe())")
        // Invalidate session pool to clear any cached sessions with old prompts
        if #available(macOS 26, *) {
            await FoundationModelsSessionPool.shared.invalidateAll()
        }
        await service.warmup()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        print("[TEST] After warmup, FoundationModelsAvailability.probe(): \(FoundationModelsAvailability.probe())")
    }

    @Test("Standard bucket generates 5 quality signoffs with S-tier examples")
    func standardBucketWithSTierExamples() async throws {
        try requireLiveTestsEnabled()
        try await warmup()
        var results: [String] = []
        var attempts = 0
        let maxAttempts = 25 // Allow more attempts since we're being strict

        while results.count < 5 && attempts < maxAttempts {
            attempts += 1
            print("\nAttempt \(attempts)/\(maxAttempts):")
            
            let outcome = await service.generateRaw(
                bucketId: "standard",
                profile: nil,
                recentTexts: [],
                toneValue: nil,
                postfixMode: .nothing,
                customInstructions: sTierExamples,
                phraseList: nil,
                ageGroup: .genZ,
                preferredRegister: nil
            )

            if case .success(let outcome) = outcome {
                let text = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
                print("  Generated: \"\(text)\"")
                
                // Validate using STRICT criteria matching the service
                if validateSignoffStrict(text) {
                    print("  ✅ VALID")
                    results.append(text)
                } else {
                    print("  ❌ INVALID - fails strict validation")
                }
            } else if case .providerFailed(let reason) = outcome {
                print("  ❌ PROVIDER FAILED: \(reason)")
            } else if case .usageLimitReached = outcome {
                print("  ❌ USAGE LIMIT REACHED")
                break
            }
            
            // Wait between attempts to avoid rate limiting
            if attempts < maxAttempts && results.count < 5 {
                print("  Waiting 2 seconds before next attempt...")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }

        print("\n=== Standard bucket results with S-tier examples ===")
        for (i, r) in results.enumerated() { print("\(i+1). \(r)") }

        // Quality assertions - we want exactly 5 successful generations
        #expect(results.count == 5, "Expected 5 successful generations, got \(results.count)")

        // Additional quality checks
        for r in results {
            #expect(hasCleanTerminus(r), "Must end with comma/period/letter: \(r)")
        }
        #expect(bananaSentinel(results), "Banana-fixation regression detected")
        #expect(Set(results).count == 5, "All signoffs must be unique")
    }

    @Test("Professional bucket generates 5 quality signoffs with S-tier examples")
    func professionalBucketWithSTierExamples() async throws {
        try requireLiveTestsEnabled()
        try await warmup()
        var results: [String] = []
        var attempts = 0
        let maxAttempts = 25

        while results.count < 5 && attempts < maxAttempts {
            attempts += 1
            print("\nAttempt \(attempts)/\(maxAttempts):")
            
            let outcome = await service.generateRaw(
                bucketId: "professional",
                profile: nil,
                recentTexts: [],
                toneValue: nil,
                postfixMode: .nothing,
                customInstructions: sTierExamples,
                phraseList: nil,
                ageGroup: .genZ,
                preferredRegister: nil
            )

            if case .success(let outcome) = outcome {
                let text = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
                print("  Generated: \"\(text)\"")
                
                if validateSignoffStrict(text) {
                    print("  ✅ VALID")
                    results.append(text)
                } else {
                    print("  ❌ INVALID - fails strict validation")
                }
            } else if case .providerFailed(let reason) = outcome {
                print("  ❌ PROVIDER FAILED: \(reason)")
            } else if case .usageLimitReached = outcome {
                print("  ❌ USAGE LIMIT REACHED")
                break
            }
            
            if attempts < maxAttempts && results.count < 5 {
                print("  Waiting 2 seconds before next attempt...")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }

        print("\n=== Professional bucket results with S-tier examples ===")
        for (i, r) in results.enumerated() { print("\(i+1). \(r)") }

        #expect(results.count == 5, "Expected 5 successful generations, got \(results.count)")

        for r in results {
            #expect(hasCleanTerminus(r), "Must end with comma/period/letter: \(r)")
        }
        #expect(Set(results).count == 5, "All signoffs must be unique")
    }

    @Test("Unhinged bucket generates 5 quality signoffs with S-tier examples")
    func unhingedBucketWithSTierExamples() async throws {
        try requireLiveTestsEnabled()
        try await warmup()
        var results: [String] = []
        var attempts = 0
        let maxAttempts = 25

        while results.count < 5 && attempts < maxAttempts {
            attempts += 1
            print("\nAttempt \(attempts)/\(maxAttempts):")
            
            let outcome = await service.generateRaw(
                bucketId: "unhinged",
                profile: nil,
                recentTexts: [],
                toneValue: nil,
                postfixMode: .nothing,
                customInstructions: sTierExamples,
                phraseList: nil,
                ageGroup: .genZ,
                preferredRegister: nil
            )

            if case .success(let outcome) = outcome {
                let text = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
                print("  Generated: \"\(text)\"")
                
                if validateSignoffStrict(text) {
                    print("  ✅ VALID")
                    results.append(text)
                } else {
                    print("  ❌ INVALID - fails strict validation")
                }
            } else if case .providerFailed(let reason) = outcome {
                print("  ❌ PROVIDER FAILED: \(reason)")
            } else if case .usageLimitReached = outcome {
                print("  ❌ USAGE LIMIT REACHED")
                break
            }
            
            if attempts < maxAttempts && results.count < 5 {
                print("  Waiting 2 seconds before next attempt...")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }

        print("\n=== Unhinged bucket results with S-tier examples ===")
        for (i, r) in results.enumerated() { print("\(i+1). \(r)") }

        #expect(results.count == 5, "Expected 5 successful generations, got \(results.count)")

        for r in results {
            #expect(hasCleanTerminus(r), "Must end with comma/period/letter: \(r)")
        }
        #expect(bananaSentinel(results), "Banana-fixation regression detected")
        #expect(Set(results).count == 5, "All signoffs must be unique")
    }
}
