import Testing
import Foundation
@testable import SignoffCore

/// Generate 50 signoffs per bucket for manual judgment of CEO/Universal/Redundancy tests.
/// Uses the same parameters as OneByOneTest but collects raw generations without human intervention.
@MainActor
struct Generate50ForJudgmentTest {
    private let service = GenerationService.shared
    // private let validator = SignoffQualityValidator.shared   // hint-only

    private let targetCount = 50
    private let historyDir = "/tmp/signoff-1x1-judgment"
    private let tones = [0.2, 0.5, 0.8]
    private let standardRegisterCycle = [
        "deadpan-closer",
        "pop-culture-catchphrase",
        "deadpan-closer",
    ]

    // ---- temp-file helpers -------------------------------------------------

    private func streakURL(_ bucket: String) -> URL {
        URL(fileURLWithPath: "\(historyDir)/\(bucket).streak")
    }

    private func historyURL(_ bucket: String) -> URL {
        URL(fileURLWithPath: "\(historyDir)/\(bucket).json")
    }

    private func rollURL(_ bucket: String) -> URL {
        URL(fileURLWithPath: "\(historyDir)/\(bucket).roll")
    }

    private func currentRoll(_ bucket: String) -> Int {
        guard let s = try? String(contentsOf: rollURL(bucket)).trimmingCharacters(in: .whitespacesAndNewlines),
              let n = Int(s) else { return 0 }
        return n
    }

    private func bumpRoll(_ bucket: String) {
        let n = currentRoll(bucket) + 1
        try? "\(n)".write(to: rollURL(bucket), atomically: true, encoding: .utf8)
    }

    private func currentStreak(_ bucket: String) -> Int {
        guard let s = try? String(contentsOf: streakURL(bucket)).trimmingCharacters(in: .whitespacesAndNewlines),
              let n = Int(s) else { return 0 }
        return n
    }

    private func loadHistory(_ bucket: String) -> [String] {
        let url = historyURL(bucket)
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return [] }
        return Array(arr.suffix(60))
    }

    private func appendHistory(_ text: String, _ bucket: String) {
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: historyDir),
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        var arr = loadHistory(bucket)
        arr.append(text)
        if arr.count > 60 { arr.removeFirst(arr.count - 60) }
        try? JSONSerialization.data(withJSONObject: arr).write(to: historyURL(bucket))
    }

    // ---- single generation --------------------------------------------------

    @Test("Generate 50 raw signoffs per bucket for judgment")
    func generate50ForJudgment() async throws {
        try requireLiveTestsEnabled()
        await warmup()

        let bucketIds = ["professional", "unhinged", "standard"]

        for bucket in bucketIds {
            print("\n\n=== PROCESSING BUCKET: \(bucket) ===")

            var history: [String] = [] // recentTexts for generateRaw
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

                // Generate raw (includes internal mechanical retries)
                // Pass empty recentTexts so each generation attempt is independent (no history bias)
                let outcome = await service.generateRaw(
                    bucketId: bucket,
                    profile: nil,
                    recentTexts: history, // use our own recent history (accepted signoffs)
                    toneValue: tones[results.count % tones.count],
                    postfixMode: .nothing,
                    customInstructions: nil,
                    phraseList: nil,
                    ageGroup: .genZ,
                    preferredRegister: (bucket == "standard") ? standardRegisterCycle[results.count % standardRegisterCycle.count] : nil
                )

                switch outcome {
                case .success(let outcome):
                    let text = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    print("\(String(format: "%2d", results.count + 1)): Generated: '\(text)'")

                    // Add to history and results (we accept every generation for now, will judge later)
                    history.append(text)
                    results.append(text)

                    // Keep history at a reasonable size (last 60)
                    if history.count > 60 {
                        history.removeFirst(history.count - 60)
                    }

                case .providerFailed(let reason):
                    print("\(String(format: "%2d", results.count + 1)): Provider failed: \(reason)")
                    // Do not add to history, try again
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
            try? output.write(to: URL(fileURLWithPath: "/tmp/\(bucket)_signoffs.txt"), atomically: true, encoding: .utf8)
            print("Saved to /tmp/\(bucket)_signoffs.txt")

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
        print("[Judgment] FMF probe: \(FoundationModelsAvailability.probe())")
        if #available(macOS 26, *) {
            await FoundationModelsSessionPool.shared.invalidateAll()
        }
        await service.warmup()
        try? await Task.sleep(nanoseconds: 100_000_000)
        print("[Judgment] After warmup FMF probe: \(FoundationModelsAvailability.probe())")
    }
}