import Testing
import Foundation
@testable import SignoffCore

/// Collect 50 fresh signoffs per bucket from the model, one at a time.
/// This mimics OneByOneTest but collects without human judgment.
@MainActor
struct Collect50FreshSignoffs {
    private let service = GenerationService.shared
    private let targetCount = 50
    private let historyDir = "/tmp/signoff-1x1-collection"

    // Register cycles matching OneByOneTest
    private let standardRegisterCycle = [
        "deadpan-closer",
        "pop-culture-catchphrase",
        "deadpan-closer",
    ]
    private let professionalRegisterCycle = [
        "deadpan-closer",
        "pop-culture-catchphrase",
        "deadpan-closer",
    ]
    private let unhingedRegisterCycle = [
        "deadpan-closer",
        "pop-culture-catchphrase",
        "deadpan-closer",
    ]

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

    @Test("Collect 50 fresh signoffs per bucket from model")
    func collect50FreshSignoffs() async throws {
        await warmup()

        let bucketConfigs: [(String, [String])] = [
            ("professional", professionalRegisterCycle),
            ("unhinged", unhingedRegisterCycle),
            ("standard", standardRegisterCycle),
        ]

        for (bucket, registerCycle) in bucketConfigs {
            print("\n\n=== COLLECTING FOR BUCKET: \(bucket) ===")
            // Clear history and collected files for this bucket
            try? FileManager.default.removeItem(at: historyURL(bucket))
            try? FileManager.default.removeItem(at: collectedURL(bucket))

            var history: [String] = []
            var collected: [String] = []
            var registerIndex = 0
            var attempts = 0
            let maxAttemptsPerSignoff = 10 // To avoid infinite loops

            while collected.count < targetCount && attempts < targetCount * maxAttemptsPerSignoff {
                attempts += 1

                let fmReady = service.isFoundationModelsReady()
                if !fmReady {
                    print("Foundation Models not ready, breaking")
                    break
                }

                // Get current register for cycling
                let currentRegister = registerCycle[registerIndex % registerCycle.count]
                registerIndex += 1

                // Generate raw with current history (to avoid ruts) and register guidance
                let outcome = await service.generateRaw(
                    bucketId: bucket,
                    profile: nil,
                    recentTexts: history, // use our own history (accepted signoffs)
                    toneValue: nil, // no tone guidance
                    postfixMode: .nothing,
                    customInstructions: nil,
                    phraseList: nil,
                    ageGroup: .genZ,
                    preferredRegister: currentRegister
                )

                switch outcome {
                case .success(let outcome):
                    let text = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    print("\(String(format: "%2d", collected.count + 1)): \(bucket) | \(text)")
                    // Accept the signoff (we're collecting for judgment)
                    collected.append(text)
                    history.append(text)
                    // Keep history at a reasonable size (last 60)
                    if history.count > 60 {
                        history.removeFirst(history.count - 60)
                    }
                    saveHistory(history, bucket)
                    appendCollected(text, bucket)

                case .providerFailed(let reason):
                    print("\(String(format: "%2d", collected.count + 1)): \(bucket) failed: \(reason)")
                case .usageLimitReached:
                    print("\(String(format: "%2d", collected.count + 1)): \(bucket) usage limit reached")
                    break
                }

                // Small delay between attempts
                try? await Task.sleep(nanoseconds: 500_000_000)
            }

            print("\n=== RESULTS FOR \(bucket) ===")
            print("Collected \(collected.count)/\(targetCount) signoffs after \(attempts) attempts")

            // Save results to file for later judgment
            let output = collected.joined(separator: "\n")
            try? output.write(to: URL(fileURLWithPath: "/tmp/\(bucket)_fresh_signoffs.txt"), atomically: true, encoding: .utf8)
            print("Saved to /tmp/\(bucket)_fresh_signoffs.txt")
        }
    }

    private func warmup() async {
        print("[Collection] FMF probe: \(FoundationModelsAvailability.probe())")
        if #available(macOS 26, *) {
            await FoundationModelsSessionPool.shared.invalidateAll()
        }
        await service.warmup()
        try? await Task.sleep(nanoseconds: 100_000_000)
        print("[Collection] After warmup FMF probe: \(FoundationModelsAvailability.probe())")
    }
}