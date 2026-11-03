import Testing
import Foundation
@testable import SignoffCore

/// Test to generate 5 valid signoffs in a row from each bucket with S-tier examples as custom instructions
@MainActor
struct FiveInARowTest {

    private let service = GenerationService.shared

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

    @Test("Generate 5 valid signoffs in a row from standard bucket with S-tier examples")
    func fiveInARowStandard() async throws {
        try await warmup()

        print("\n=== STARTING STANDARD BUCKET TEST ===")
        print("Attempting to generate 5 valid signoffs in a row...")

        var successes = 0
        var attempts = 0
        let maxAttempts = 20 // Allow up to 20 attempts to get 5 in a row

        while successes < 5 && attempts < maxAttempts {
            attempts += 1
            print("\nAttempt \(attempts)/\(maxAttempts): Current streak = \(successes)/5")

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

                if validateSignoffStrict(text) {
                    print("  ✅ VALID - Streak: \(successes + 1)/5")
                    successes += 1
                } else {
                    print("  ❌ INVALID - fails strict validation, resetting streak")
                    successes = 0
                }
            } else if case .providerFailed(let reason) = outcome {
                print("  ❌ PROVIDER FAILED: \(reason)")
                // Provider failures don't break the streak necessarily, but we don't count them as successes
                // In practice, we might want to wait longer on provider failures
            } else if case .usageLimitReached = outcome {
                print("  ❌ USAGE LIMIT REACHED")
                break
            }

            // Wait between attempts to avoid rate limiting or state conflicts
            if attempts < maxAttempts {
                print("  Waiting 2 seconds before next attempt...")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }

        print("\n=== STANDARD BUCKET RESULTS ===")
        print("Successful generations in a row: \(successes)/5")
        print("Total attempts: \(attempts)")

        if successes == 5 {
            print("🎉 SUCCESS: Got 5 valid generations in a row!")
        } else {
            print("❌ FAILED: Did not get 5 successful generations in a row")
            #expect(Bool(false), "Expected 5 consecutive valid generations from standard bucket, got \(successes)")
        }

        #expect(successes == 5, "Expected 5 consecutive valid generations from standard bucket")
    }

    @Test("Generate 5 valid signoffs in a row from professional bucket with S-tier examples")
    func fiveInARowProfessional() async throws {
        try await warmup()

        print("\n=== STARTING PROFESSIONAL BUCKET TEST ===")
        print("Attempting to generate 5 valid signoffs in a row...")

        var successes = 0
        var attempts = 0
        let maxAttempts = 20

        while successes < 5 && attempts < maxAttempts {
            attempts += 1
            print("\nAttempt \(attempts)/\(maxAttempts): Current streak = \(successes)/5")

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
                    print("  ✅ VALID - Streak: \(successes + 1)/5")
                    successes += 1
                } else {
                    print("  ❌ INVALID - fails strict validation, resetting streak")
                    successes = 0
                }
            } else if case .providerFailed(let reason) = outcome {
                print("  ❌ PROVIDER FAILED: \(reason)")
            } else if case .usageLimitReached = outcome {
                print("  ❌ USAGE LIMIT REACHED")
                break
            }

            // Wait between attempts to avoid rate limiting or state conflicts
            if attempts < maxAttempts {
                print("  Waiting 2 seconds before next attempt...")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }

        print("\n=== PROFESSIONAL BUCKET RESULTS ===")
        print("Successful generations in a row: \(successes)/5")
        print("Total attempts: \(attempts)")

        if successes == 5 {
            print("🎉 SUCCESS: Got 5 valid generations in a row!")
        } else {
            print("❌ FAILED: Did not get 5 successful generations in a row")
            #expect(Bool(false), "Expected 5 consecutive valid generations from professional bucket, got \(successes)")
        }

        #expect(successes == 5, "Expected 5 consecutive valid generations from professional bucket")
    }

    @Test("Generate 5 valid signoffs in a row from unhinged bucket with S-tier examples")
    func fiveInARowUnhinged() async throws {
        try await warmup()

        print("\n=== STARTING UNHINGED BUCKET TEST ===")
        print("Attempting to generate 5 valid signoffs in a row...")

        var successes = 0
        var attempts = 0
        let maxAttempts = 20

        while successes < 5 && attempts < maxAttempts {
            attempts += 1
            print("\nAttempt \(attempts)/\(maxAttempts): Current streak = \(successes)/5")

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
                    print("  ✅ VALID - Streak: \(successes + 1)/5")
                    successes += 1
                } else {
                    print("  ❌ INVALID - fails strict validation, resetting streak")
                    successes = 0
                }
            } else if case .providerFailed(let reason) = outcome {
                print("  ❌ PROVIDER FAILED: \(reason)")
            } else if case .usageLimitReached = outcome {
                print("  ❌ USAGE LIMIT REACHED")
                break
            }

            // Wait between attempts to avoid rate limiting or state conflicts
            if attempts < maxAttempts {
                print("  Waiting 2 seconds before next attempt...")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }

        print("\n=== UNHINGED BUCKET RESULTS ===")
        print("Successful generations in a row: \(successes)/5")
        print("Total attempts: \(attempts)")

        if successes == 5 {
            print("🎉 SUCCESS: Got 5 valid generations in a row!")
        } else {
            print("❌ FAILED: Did not get 5 successful generations in a row")
            #expect(Bool(false), "Expected 5 consecutive valid generations from unhinged bucket, got \(successes)")
        }

        #expect(successes == 5, "Expected 5 consecutive valid generations from unhinged bucket")
    }
}