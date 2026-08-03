import Testing
import Foundation
@testable import SignoffCore

/// Batch quality validation — generates 50 signoffs per bucket for manual review.
/// Run with: swift test --filter "BatchQualityValidationTests"
/// Serialized because Foundation Models rejects concurrent requests system-wide.
@MainActor
@Suite(.serialized)
struct BatchQualityValidationTests {

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

    // Warm up model and invalidate session pool
    private func warmup() async {
        print("[BATCH] FoundationModelsAvailability.probe(): \(FoundationModelsAvailability.probe())")
        if #available(macOS 26, *) {
            await FoundationModelsSessionPool.shared.invalidateAll()
        }
        await service.warmup()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        print("[BATCH] After warmup, FoundationModelsAvailability.probe(): \(FoundationModelsAvailability.probe())")
    }

    /// Generate 50 signoffs for a bucket with full validation
    private func generateBucket(bucketId: String, count: Int = 50, toneValue: Double? = nil, unhingedLevel: UnhingedLevel? = nil) async throws -> [String] {
        try await warmup()
        var results: [String] = []

        for i in 1...count {
            let fmReady = service.isFoundationModelsReady()
            print("[BATCH] \(bucketId) Iteration \(i)/\(count): fmReady=\(fmReady)")

            // For professional bucket, randomize tone to get variety across formal/balanced/relaxed
            let effectiveToneValue: Double?
            if bucketId == "professional" {
                // Rotate through 0.2 (formal), 0.5 (balanced), 0.8 (relaxed)
                let tones = [0.2, 0.5, 0.8]
                effectiveToneValue = tones[(i - 1) % tones.count]
            } else {
                effectiveToneValue = toneValue
            }

            // Mirror the real app: consecutive generations carry recent history
            // so the validator's similarity/dedup check engages. This is the
            // regime the user's "20 in a row" bar describes, and it is what
            // naturally suppresses verbal-tics ("Counting X," ×8) across
            // back-to-back outputs. Pass the accepted results so far.
            let result = await service.generate(
                bucketId: bucketId,
                profile: nil,
                recentTexts: results,
                unhingedLevel: unhingedLevel,
                toneValue: effectiveToneValue,
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
                Issue.record("Generation failed for \(bucketId) bucket at iteration \(i)")
            }
            // Small delay between generations
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        return results
    }

    @Test("Batch: Generate 50 Standard bucket signoffs")
    func batchStandardBucket() async throws {
        let results = try await generateBucket(bucketId: "standard", count: 50)

        print("\n=== BATCH STANDARD BUCKET RESULTS (50) ===")
        for (i, r) in results.enumerated() {
            print("\(i+1). \(r)")
        }

        // Automated quality gates
        #expect(results.count == 50, "Must generate exactly 50")

        var validatorFailures: [String] = []
        var terminusFailures: [String] = []

        for r in results {
            switch SignoffQualityValidator.shared.validate(r, forBucket: "standard", recentHistory: []) {
            case .valid: break
            case .invalid(let reason):
                validatorFailures.append("\"\(r)\": \(reason)")
            }
            if !hasCleanTerminus(r) {
                terminusFailures.append(r)
            }
        }

        #expect(validatorFailures.isEmpty, "Validator rejected \(validatorFailures.count): \(validatorFailures.joined(separator: "; "))")
        #expect(terminusFailures.isEmpty, "Bad terminus: \(terminusFailures.joined(separator: "; "))")
        #expect(bananaSentinel(results), "Banana-fixation regression detected or too few unique")

        // Uniqueness check - at least 30% unique
        let uniqueCount = Set(results).count
        #expect(uniqueCount >= 15, "Too few unique signoffs: \(uniqueCount)/50")

        print("\n=== STANDARD SUMMARY ===")
        print("Total: \(results.count)")
        print("Unique: \(uniqueCount)")
        print("Validator failures: \(validatorFailures.count)")
        print("Terminus failures: \(terminusFailures.count)")
        print("Banana sentinel: \(bananaSentinel(results))")
    }

    @Test("Batch: Generate 50 Professional bucket signoffs")
    func batchProfessionalBucket() async throws {
        let results = try await generateBucket(bucketId: "professional", count: 50, toneValue: 0.5)

        print("\n=== BATCH PROFESSIONAL BUCKET RESULTS (50) ===")
        for (i, r) in results.enumerated() {
            print("\(i+1). \(r)")
        }

        #expect(results.count == 50, "Must generate exactly 50")

        var validatorFailures: [String] = []
        var terminusFailures: [String] = []

        for r in results {
            switch SignoffQualityValidator.shared.validate(r, forBucket: "professional", recentHistory: []) {
            case .valid: break
            case .invalid(let reason):
                validatorFailures.append("\"\(r)\": \(reason)")
            }
            if !hasCleanTerminus(r) {
                terminusFailures.append(r)
            }
        }

        #expect(validatorFailures.isEmpty, "Validator rejected \(validatorFailures.count): \(validatorFailures.joined(separator: "; "))")
        #expect(terminusFailures.isEmpty, "Bad terminus: \(terminusFailures.joined(separator: "; "))")

        let uniqueCount = Set(results).count
        // Professional closers are conventional by design — a small set of
        // credible closers ("Warm regards," "Respectfully," "Many thanks,")
        // repeating across 50 generations is correct, not a defect. The real
        // quality bar is: every output makes sense, is credible, and is never
        // word salad or demeaning. Require ≥6 distinct credible closers.
        let minUnique = 6
        #expect(uniqueCount >= minUnique, "Too few unique signoffs: \(uniqueCount)/50")

        print("\n=== PROFESSIONAL SUMMARY ===")
        print("Total: \(results.count)")
        print("Unique: \(uniqueCount)")
        print("Validator failures: \(validatorFailures.count)")
        print("Terminus failures: \(terminusFailures.count)")
    }

    @Test("Batch: Generate 50 Unhinged bucket signoffs")
    func batchUnhingedBucket() async throws {
        let results = try await generateBucket(bucketId: "unhinged", count: 50, unhingedLevel: .cynical)

        print("\n=== BATCH UNHINGED BUCKET RESULTS (50) ===")
        for (i, r) in results.enumerated() {
            print("\(i+1). \(r)")
        }

        #expect(results.count == 50, "Must generate exactly 50")

        var validatorFailures: [String] = []
        var terminusFailures: [String] = []

        for r in results {
            switch SignoffQualityValidator.shared.validate(r, forBucket: "unhinged", recentHistory: []) {
            case .valid: break
            case .invalid(let reason):
                validatorFailures.append("\"\(r)\": \(reason)")
            }
            if !hasCleanTerminus(r) {
                terminusFailures.append(r)
            }
        }

        #expect(validatorFailures.isEmpty, "Validator rejected \(validatorFailures.count): \(validatorFailures.joined(separator: "; "))")
        #expect(terminusFailures.isEmpty, "Bad terminus: \(terminusFailures.joined(separator: "; "))")
        #expect(bananaSentinel(results), "Banana-fixation regression detected or too few unique")

        let uniqueCount = Set(results).count
        #expect(uniqueCount >= 15, "Too few unique unhinged signoffs: \(uniqueCount)/50")

        print("\n=== UNHINGED SUMMARY ===")
        print("Total: \(results.count)")
        print("Unique: \(uniqueCount)")
        print("Validator failures: \(validatorFailures.count)")
        print("Terminus failures: \(terminusFailures.count)")
        print("Banana sentinel: \(bananaSentinel(results))")
    }
}