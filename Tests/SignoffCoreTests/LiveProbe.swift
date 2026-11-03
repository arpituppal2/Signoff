import Testing
import Foundation
@testable import SignoffCore

@MainActor
@Suite(.serialized)
struct LiveProbe {
    private let service = GenerationService.shared

    @Test func probeUnhingedShipped() async throws {
        guard ProcessInfo.processInfo.environment["SIGNOFF_RUN_LIVE_TESTS"] == "1" else { print("SKIP"); return }
        await service.warmup()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        var ok = 0, fail = 0
        let rounds = Int(ProcessInfo.processInfo.environment["ROUNDS"] ?? "10") ?? 10
        for i in 1...rounds {
            let r = await service.generate(
                bucketId: "unhinged", profile: nil, recentTexts: [],
                unhingedLevel: .cynical, toneValue: nil, postfixMode: .nothing,
                customInstructions: nil, phraseList: nil, ageGroup: .genZ,
                nsfwEnabled: false, bypassCache: true)
            if case .success(let o) = r {
                ok += 1; print("SHIP \(i): \(o.text)")
            } else if case .providerFailed(let reason) = r {
                fail += 1; print("SHIP \(i): FAIL — \(reason)")
            } else {
                fail += 1; print("SHIP \(i): FAIL — usageLimit")
            }
        }
        print("RESULT ok=\(ok) fail=\(fail)")
    }
}
