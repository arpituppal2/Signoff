import Testing
import Foundation
@testable import SignoffCore

/// Diagnostic: 20 generations per bucket printing EACH attempt's OK/FAIL.
/// Run all:  swift test --filter "DiagnosticBatchTests"
/// Run one:  swift test --filter "DiagnosticBatchTests.diagUnhinged"
/// @Suite(.serialized) — Foundation Models rejects concurrent requests.
@MainActor
@Suite(.serialized)
struct DiagnosticBatchTests {

    private func runDiag(bucketId: String, tag: String, unhingedLevel: UnhingedLevel?,
                          toneValue: Double? = nil) async throws -> Int {
        await GenerationService.shared.warmup()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        var results: [String] = []
        for i in 1...20 {
            // Read the DEBUG probe's lastEvent after each gen — it records
            // the most recent validation-fail reason (recordEvent is called
            // on every invalid attempt, so lastEvent before the final FAIL
            // shows the LAST reject reason that killed the 8th attempt).
            GenerationDebugProbe.shared.recordEvent("== GEN \(i) START ==")
            let r = await GenerationService.shared.generate(
                bucketId: bucketId, profile: nil, recentTexts: results,
                unhingedLevel: unhingedLevel, toneValue: toneValue, postfixMode: .nothing,
                customInstructions: nil, phraseList: nil, ageGroup: .genZ,
                nsfwEnabled: false, bypassCache: true)
            let lastInnerReason = GenerationDebugProbe.shared.lastEvent
            switch r {
            case .success(let o):
                results.append(o.text)
                print("[\(tag) \(i)/20] OK: \(o.text)")
            case .providerFailed(let reason):
                print("[\(tag) \(i)/20] FAIL: \(reason)")
                print("       last reject: \(lastInnerReason.isEmpty ? "(empty — model threw / 0 attempts)" : lastInnerReason)")
            case .usageLimitReached:
                print("[\(tag) \(i)/20] LIMIT")
            }
        }
        print("\n=== \(tag) SUMMARY: \(results.count)/20 succeeded, \(20-results.count) failed ===")
        return results.count
    }

    @Test("Diagnostic: 20 unhinged with reject reasons")
    func diagUnhinged() async throws {
        let n = try await runDiag(bucketId: "unhinged", tag: "DIAG", unhingedLevel: .cynical)
        #expect(n >= 18, "Error rate too high: \(20-n)/20 failed (>1% bar means ≤0 failures in 20)")
    }

    @Test("Diagnostic: 20 general/standard")
    func diagGeneral() async throws {
        let n = try await runDiag(bucketId: "standard", tag: "GEN", unhingedLevel: nil, toneValue: 0.5)
        #expect(n >= 18, "General error rate too high: \(20-n)/20 failed")
    }

    @Test("Diagnostic: 20 professional")
    func diagProfessional() async throws {
        let n = try await runDiag(bucketId: "professional", tag: "PRO", unhingedLevel: nil, toneValue: 0.5)
        #expect(n >= 18, "Professional error rate too high: \(20-n)/20 failed")
    }
}
