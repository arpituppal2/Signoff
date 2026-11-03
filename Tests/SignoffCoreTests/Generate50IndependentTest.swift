import Testing
import Foundation
@testable import SignoffCore

/// Generate 50 raw signoffs per bucket with empty recentTexts each time (truly from scratch).
@MainActor
struct Generate50IndependentTest {
    private let service = GenerationService.shared
    // private let validator = SignoffQualityValidator.shared   // for optional validation hint

    private let targetCount = 50
    private let tones = [0.2, 0.5, 0.8]
    private let standardRegisterCycle = [
        "deadpan-closer",
        "pop-culture-catchphrase",
        "deadpan-closer",
    ]

    @Test("Generate 50 raw signoffs per bucket with empty history")
    func generate50Independent() async throws {
        try requireLiveTestsEnabled()
        await warmup()

        let bucketIds = ["professional", "unhinged", "standard"]

        for bucket in bucketIds {
            print("\n\n=== PROCESSING BUCKET: \(bucket) ===")

            var results: [String] = []
            var attempts = 0
            let maxAttemptsPerSignoff = 5 // To avoid infinite loops

            while results.count < targetCount && attempts < targetCount * maxAttemptsPerSignoff {
                attempts += 1

                let fmReady = service.isFoundationModelsReady()
                if !fmReady {
                    print("Foundation Models not ready, breaking")
                    break
                }

                // Generate raw with empty recentTexts (no history) and no tone/register guidance
                // to see what the model produces from scratch.
                let outcome = await service.generateRaw(
                    bucketId: bucket,
                    profile: nil,
                    recentTexts: [], // empty history each time
                    toneValue: nil, // no tone guidance
                    postfixMode: .nothing,
                    customInstructions: nil,
                    phraseList: nil,
                    ageGroup: .genZ,
                    preferredRegister: nil // no register guidance
                )

                switch outcome {
                case .success(let outcome):
                    let text = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    print("\(String(format: "%2d", results.count + 1)): Generated: '\(text)'")
                    results.append(text)

                case .providerFailed(let reason):
                    print("\(String(format: "%2d", results.count + 1)): Provider failed: \(reason)")
                case .usageLimitReached:
                    print("\(String(format: "%2d", results.count + 1)): Usage limit reached")
                    break
                }

                // Small delay between attempts
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            print("\n=== RESULTS FOR \(bucket) ===")
            print("Generated \(results.count)/\(targetCount) signoffs after \(attempts) attempts")

            // Save results to file for later judgment
            let output = results.joined(separator: "\n")
            try? output.write(to: URL(fileURLWithPath: "/tmp/\(bucket)_independent_signoffs.txt"), atomically: true, encoding: .utf8)
            print("Saved to /tmp/\(bucket)_independent_signoffs.txt")

            // Also print them as a list for easy copying
            print("\n--- LIST ---")
            for (i, signoff) in results.enumerated() {
                print("\(i+1). \(signoff)")
            }
        }
    }

    private func requireLiveTestsEnabled() throws {
        guard ProcessInfo.processInfo.environment["SIGNOFF_RUN_LIVE_TESTS"] == "1" else {
            throw NSError(domain: "SignoffLiveTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Set SIGNOFF_RUN_LIVE_TESTS=1 to run live Foundation Models tests."])
        }
    }

    private func warmup() async {
        print("[Independent] FMF probe: \(FoundationModelsAvailability.probe())")
        if #available(macOS 26, *) {
            await FoundationModelsSessionPool.shared.invalidateAll()
        }
        await service.warmup()
        try? await Task.sleep(nanoseconds: 100_000_000)
        print("[Independent] After warmup FMF probe: \(FoundationModelsAvailability.probe())")
    }
}