import Testing
import Foundation
@testable import SignoffCore

/// Test generation quality across all buckets - ensures phrases are not word salad
/// Serialized because Foundation Models rejects concurrent requests system-wide.
@MainActor
@Suite(.serialized)
struct GenerationQualityTests {

    private let service = GenerationService.shared
    private let buckets = ["standard", "professional", "unhinged"]

    private func requireLiveTestsEnabled() throws {
        guard ProcessInfo.processInfo.environment["SIGNOFF_RUN_LIVE_TESTS"] == "1" else {
            throw NSError(domain: "SignoffLiveTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Set SIGNOFF_RUN_LIVE_TESTS=1 to run live Foundation Models tests."])
        }
    }

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

    @Test("Standard bucket generates quality signoffs")
    func standardBucketGeneratesQualitySignoffs() async throws {
        try requireLiveTestsEnabled()
        try await warmup()
        var results: [String] = []

        for i in 1...10 {
            let fmReady = service.isFoundationModelsReady()
            print("[TEST] Iteration \(i): fmReady=\(fmReady)")
            let result = await service.generate(
                bucketId: "standard",
                profile: nil,
                recentTexts: [],
                unhingedLevel: nil,
                toneValue: nil,
                postfixMode: .nothing,
                customInstructions: nil,
                phraseList: nil,
                ageGroup: .genZ,
                nsfwEnabled: false,
                bypassCache: true // Force live generation
            )

            if case .success(let outcome) = result {
                results.append(outcome.text)
            } else {
                Issue.record("Generation failed for standard bucket")
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        print("=== Standard bucket results ===")
        for (i, r) in results.enumerated() { print("\(i+1). \(r)") }

        // Quality assertions
        #expect(results.count == 10)

        // Validator deleted per user request — terminal-shape checks remain as
        // a hard backstop against model narration/empty output.
        for r in results {
            #expect(hasCleanTerminus(r), "Must end with comma/period/letter: \(r)")
        }
        #expect(bananaSentinel(results), "Banana-fixation regression detected")
    }

    @Test("Professional bucket generates quality signoffs")
    func professionalBucketGeneratesQualitySignoffs() async throws {
        try requireLiveTestsEnabled()
        try await warmup()
        var results: [String] = []

        for _ in 1...10 {
            let result = await service.generate(
                bucketId: "professional",
                profile: nil,
                recentTexts: [],
                unhingedLevel: nil,
                toneValue: 0.5,
                postfixMode: .nothing,
                customInstructions: nil,
                phraseList: nil,
                ageGroup: .genZ,
                nsfwEnabled: false,
                bypassCache: true
            )

            if case .success(let outcome) = result {
                results.append(outcome.text)
            } else {
                Issue.record("Generation failed for professional bucket")
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        print("=== Professional bucket results ===")
        for (i, r) in results.enumerated() { print("\(i+1). \(r)") }

        #expect(results.count == 10)

        for r in results {
            #expect(hasCleanTerminus(r), "Must end with comma/period/letter: \(r)")
        }
    }

    @Test("Unhinged bucket generates quality signoffs")
    func unhingedBucketGeneratesQualitySignoffs() async throws {
        try requireLiveTestsEnabled()
        try await warmup()
        var results: [String] = []

        for _ in 1...10 {
            let result = await service.generate(
                bucketId: "unhinged",
                profile: nil,
                recentTexts: [],
                unhingedLevel: .cynical,
                toneValue: nil,
                postfixMode: .nothing,
                customInstructions: nil,
                phraseList: nil,
                ageGroup: .genZ,
                nsfwEnabled: false,
                bypassCache: true
            )

            if case .success(let outcome) = result {
                results.append(outcome.text)
            } else {
                Issue.record("Generation failed for unhinged bucket")
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        print("=== Unhinged bucket results ===")
        for (i, r) in results.enumerated() { print("\(i+1). \(r)") }

        #expect(results.count == 10)

        for r in results {
            #expect(hasCleanTerminus(r), "Must end with comma/period/letter: \(r)")
        }
        #expect(bananaSentinel(results), "Banana-fixation regression detected")
    }
}