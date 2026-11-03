import Testing
import Foundation
@testable import SignoffCore

@MainActor
struct TestStandardSwift {
    @Test("Test standard bucket with S-tier examples")
    func testStandardBucket() async throws {
        print("=== Testing Standard Bucket Only ===")
        
        let service = GenerationService.shared
        
        // Clear any existing state by waiting
        print("Waiting for any existing operations to complete...")
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Warm up
        print("Warming up Foundation Models...")
        await service.warmup()
        print("Warmed up")
        
        // User‑provided S‑tier examples
        let sTierExamples = """
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
        
        var successes = 0
        var attempts = 0
        let maxAttempts = 20
        
        while successes < 5 && attempts < maxAttempts {
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
            
            switch outcome {
            case .success(let result):
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                print("  Generated: \"\(text)\"")
                
                // Validate using the same criteria as the service
                let trimmed = text
                let words = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                let wordCount = words.count
                let commaCount = trimmed.filter { $0 == "," }.count
                let endsWithComma = trimmed.hasSuffix(",")
                
                // Additional validation that matches the service
                let firstWordCapitalized = words.first?.first?.isUppercase == true
                let noBannedWords = !["coffee", "drink", "beer", "wine", "whiskey"].contains { 
                    trimmed.lowercased().contains($0) 
                }
                let noSimile = trimmed.range(of: " like ", options: .caseInsensitive) == nil
                
                if wordCount >= 2 && wordCount <= 7 && 
                   commaCount == 1 && 
                   endsWithComma && 
                   firstWordCapitalized &&
                   noBannedWords &&
                   noSimile {
                    print("  ✅ VALID (word count: \(wordCount), commas: \(commaCount), ends with comma, first cap: \(firstWordCapitalized), no banned: \(noBannedWords), no simile: \(noSimile))")
                    successes += 1
                } else {
                    print("  ❌ INVALID - word count: \(wordCount) (should be 2-7), commas: \(commaCount) (should be 1), ends with comma: \(endsWithComma), first cap: \(firstWordCapitalized), no banned: \(noBannedWords), no simile: \(noSimile))")
                }
                
            case .providerFailed(let reason):
                print("  ❌ PROVIDER FAILED: \(reason)")
            case .usageLimitReached:
                print("  ❌ USAGE LIMIT REACHED")
                break
            }
            
            // Wait between attempts to avoid rate limiting or state conflicts
            if attempts < maxAttempts {
                print("  Waiting 2 seconds before next attempt...")
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        
        print("\n=== SUMMARY ===")
        print("Successful generations: \(successes)/5")
        print("Total attempts: \(attempts)")
        if successes == 5 {
            print("Success rate: 100%")
            print("🎉 SUCCESS: Got 5 valid generations in a row!")
        } else {
            let rate = Double(successes) / Double(attempts) * 100
            print("Success rate: \(String(format: "%.1f", rate))%")
            print("❌ FAILED: Did not get 5 successful generations")
        }
        
        // Expectation for the test
        #expect(successes == 5, "Expected 5 successful generations, got \(successes)")
    }
}
