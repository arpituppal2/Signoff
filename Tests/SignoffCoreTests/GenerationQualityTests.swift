import XCTest
@testable import SignoffCore

/// Test generation quality across all buckets - ensures phrases are not word salad
@MainActor
final class GenerationQualityTests: XCTestCase {

    private let service = GenerationService.shared
    private let buckets = ["standard", "professional", "unhinged"]

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

    override func setUp() async throws {
        try await super.setUp()
        // Warm up model
        print("[TEST] FoundationModelsAvailability.probe(): \(FoundationModelsAvailability.probe())")
        // Invalidate session pool to clear any cached sessions with old prompts
        if #available(macOS 26, *) {
            await FoundationModelsSessionPool.shared.invalidateAll()
        }
        await service.warmup()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        print("[TEST] After warmup, FoundationModelsAvailability.probe(): \(FoundationModelsAvailability.probe())")
    }

    func testStandardBucketGeneratesQualitySignoffs() async {
        var results: [String] = []

        for i in 1...5 {
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
                XCTFail("Generation failed for standard bucket")
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        print("=== Standard bucket results ===")
        for (i, r) in results.enumerated() { print("\(i+1). \(r)") }

        // Quality assertions
        XCTAssertEqual(results.count, 5)

        // Every result must pass the production quality gate (banned tokens,
        // n-grams, markdown, word-count range, single-line, readability).
        // The validator is the single source of truth — do not duplicate a
        // looser substring list here; it false-positives on legitimate closers
        // (e.g. banning "insight" would reject "Insightful as always,").
        for r in results {
            switch SignoffQualityValidator.shared.validate(r, forBucket: "standard", recentHistory: []) {
            case .valid: break
            case .invalid(let reason): XCTFail("Validator rejected \"\(r)\": \(reason)")
            }
            XCTAssertTrue(hasCleanTerminus(r), "Must end with comma/period/letter: \(r)")
        }
        XCTAssertTrue(bananaSentinel(results), "Banana-fixation regression detected")
    }

    func testProfessionalBucketGeneratesQualitySignoffs() async {
        var results: [String] = []

        for _ in 1...5 {
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
                XCTFail("Generation failed for professional bucket")
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        print("=== Professional bucket results ===")
        for (i, r) in results.enumerated() { print("\(i+1). \(r)") }

        XCTAssertEqual(results.count, 5)

        for r in results {
            switch SignoffQualityValidator.shared.validate(r, forBucket: "professional", recentHistory: []) {
            case .valid: break
            case .invalid(let reason): XCTFail("Validator rejected \"\(r)\": \(reason)")
            }
            XCTAssertTrue(hasCleanTerminus(r), "Must end with comma/period/letter: \(r)")
        }
    }

    func testUnhingedBucketGeneratesQualitySignoffs() async {
        var results: [String] = []

        for _ in 1...5 {
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
                XCTFail("Generation failed for unhinged bucket")
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        print("=== Unhinged bucket results ===")
        for (i, r) in results.enumerated() { print("\(i+1). \(r)") }

        XCTAssertEqual(results.count, 5)

        for r in results {
            switch SignoffQualityValidator.shared.validate(r, forBucket: "unhinged", recentHistory: []) {
            case .valid: break
            case .invalid(let reason): XCTFail("Validator rejected \"\(r)\": \(reason)")
            }
            XCTAssertTrue(hasCleanTerminus(r), "Must end with comma/period/letter: \(r)")
        }
        XCTAssertTrue(bananaSentinel(results), "Banana-fixation regression detected")
    }
}