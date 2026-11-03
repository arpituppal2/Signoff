import Testing
import Foundation
@testable import SignoffCore

/// Simple test to get 1 valid generation from each bucket with S-tier examples
@MainActor
struct SimpleTierTest {

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

    @Test("Get 1 valid generation from each bucket with S-tier examples")
    func getOneFromEachBucket() async throws {
        try await warmup()
        
        let buckets = ["standard", "professional", "unhinged"]
        let bucketNames = ["standard": "Standard", "professional": "Professional", "unhinged": "Unhinged"]
        
        for bucket in buckets {
            let bucketName = bucketNames[bucket] ?? bucket.capitalized
            print("\n=== \(bucketName) bucket ===")
            
            var success = false
            var attempts = 0
            let maxAttempts = 5
            
            while !success && attempts < maxAttempts {
                attempts += 1
                print("  Attempt \(attempts)/\(maxAttempts):")
                
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

                if case .success(let outcome) = outcome {
                    let text = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    print("    Generated: \"\(text)\"")
                    
                    if validateSignoffStrict(text) {
                        print("    ✅ VALID")
                        success = true
                    } else {
                        print("    ❌ INVALID - fails strict validation")
                    }
                } else if case .providerFailed(let reason) = outcome {
                    print("    ❌ PROVIDER FAILED: \(reason)")
                } else if case .usageLimitReached = outcome {
                    print("    ❌ USAGE LIMIT REACHED")
                    break
                }
                
                if !success && attempts < maxAttempts {
                    print("    Waiting 1 second before next attempt...")
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            
            if success {
                print("  ✅ \(bucketName) bucket: Success!")
            } else {
                print("  ❌ \(bucketName) bucket: Failed after \(maxAttempts) attempts")
                Issue.record("\(bucketName) bucket failed to generate a valid signoff")
            }
        }
    }
}
