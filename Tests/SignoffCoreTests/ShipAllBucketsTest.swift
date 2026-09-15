import Testing
import Foundation
@testable import SignoffCore

/// Exercises the SHIPPING generate() path for every bucket and prints the
/// results, so a human (or me) can verify real funny lines come out — not
/// word salad, not exhaustion errors.
@MainActor
@Suite(.serialized)
struct ShipAllBucketsTest {
    private let service = GenerationService.shared

    @Test func shipAllBuckets() async throws {
        await service.warmup()
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let buckets: [(String, String)] = [
            ("standard", "standard"),
            ("professional", "professional"),
            ("unhinged", "unhinged"),
        ]
        let rounds = Int(ProcessInfo.processInfo.environment["ROUNDS"] ?? "8") ?? 8

        for (label, id) in buckets {
            var ok = 0, fail = 0
            var lines: [String] = []
            var seen = Set<String>()
            for i in 1...rounds {
                let r = await service.generate(
                    bucketId: id, profile: nil, recentTexts: lines,
                    unhingedLevel: .cynical, toneValue: nil, postfixMode: .nothing,
                    customInstructions: nil, phraseList: nil, ageGroup: .genZ,
                    nsfwEnabled: false, bypassCache: true)
                if case .success(let o) = r {
                    ok += 1
                    lines.append(o.text)
                    let key = o.text.lowercased()
                    seen.insert(key)
                    print("[\(label)] \(i): \(o.text)")
                } else if case .providerFailed(let reason) = r {
                    fail += 1; print("[\(label)] \(i): FAIL — \(reason)")
                } else {
                    fail += 1; print("[\(label)] \(i): FAIL — usageLimit")
                }
            }
            print("=== \(label): ok=\(ok) fail=\(fail) distinct=\(seen.count) ===")
        }
    }
}