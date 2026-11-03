import Testing
import Foundation
@testable import SignoffCore

/// Generate 50 raw signoffs per bucket for judgment, automatically accepting each generation.
/// Uses history to avoid ruts, but accepts every generated signoff (no human in the loop).
@MainActor
struct Generate50ForJudgmentAutomaticTest {
    private let service = GenerationService.shared
    //    private let validator = SignoffQualityValidator.shared   // for optional validation hint

    private let targetCount = 50
    private let historyDir = "/tmp/signoff-1x1-auto"
    private let tones = [0.2, 0.5, 0.8]
    private let standardRegisterCycle = [
        "deadpan-closer",
        "pop-culture-catchphrase",
        "deadpan-closer",
    ]

    // ---- temp-file helpers -------------------------------------------------

    private func historyURL(_ bucket: String) -> URL {
        URL(fileURLWithPath: "\(historyDir)/\(bucket).json")
    }

    private func collectedURL(_ bucket: String) -> URL {
        URL(fileURLWithPath: "\(historyDir)/\(bucket)_collected.txt")
    }

    private func loadHistory(_ bucket: String) -> [String] {
        let url = historyURL(bucket)
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return [] }
        return Array(arr.suffix(60)) // keep last 60
    }

    private func saveHistory(_ history: [String], _ bucket: String) {
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: historyDir),
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        try? JSONSerialization.data(withJSONObject: history).write(to: historyURL(bucket))
    }

    private func appendCollected(_ text: String, _ bucket: String) {
        try? FileManager.default.createDirectory(at: URL(fileURLWithPath: historyDir),
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        let url = collectedURL(bucket)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            if let data = (text + "\n").data(using: .utf8) {
                handle.write(data)
            }
            try? handle.close()
        } else {
            try? (text + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // ---- single generation --------------------------------------------------

    @Test("Generate 50 raw signoffs per bucket for judgment (auto-accept)")
    func generate50ForJudgmentAutomatic() async throws {
        try requireLiveTestsEnabled()
        await warmup()

        let bucketIds = ["professional", "unhinged", "standard"]

        for bucket in bucketIds {
            print("\n\n=== PROCESSING BUCKET: \(bucket) ===")
            // Clear history and collected files for this bucket
            try? FileManager.default.removeItem(at: historyURL(bucket))
            try? FileManager.default.removeItem(at: collectedURL(bucket))

            var history: [String] = []
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

                // Generate raw with current history (to avoid ruts) but no tone/register guidance
                // to see what the model produces given the recent accepted signoffs.
                let outcome = await service.generateRaw(
                    bucketId: bucket,
                    profile: nil,
                    recentTexts: history, // use our own history (accepted signoffs)
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
                    // Accept the signoff (auto-accept)
                    results.append(text)
                    history.append(text)
                    // Keep history at a reasonable size (last 60)
                    if history.count > 60 {
                        history.removeFirst(history.count - 60)
                    }
                    saveHistory(history, bucket)
                    appendCollected(text, bucket)

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

            // Save results to file for later judgment (we already appended, but let's also write the whole array)
            let output = results.joined(separator: "\n")
            try? output.write(to: URL(fileURLWithPath: "/tmp/\(bucket)_auto_signoffs.txt"), atomically: true, encoding: .utf8)
            print("Saved to /tmp/\(bucket)_auto_signoffs.txt")

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
        print("[Auto] FMF probe: \(FoundationModelsAvailability.probe())")
        if #available(macOS 26, *) {
            await FoundationModelsSessionPool.shared.invalidateAll()
        }
        await service.warmup()
        try? await Task.sleep(nanoseconds: 100_000_000)
        print("[Auto] After warmup FMF probe: \(FoundationModelsAvailability.probe())")
    }
}