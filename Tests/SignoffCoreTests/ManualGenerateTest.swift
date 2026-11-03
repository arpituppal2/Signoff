import Testing
import Foundation
@testable import SignoffCore

@MainActor
@Suite(.serialized)
struct ManualGenerateTest {

    private let service = GenerationService.shared

    private func requireLiveTestsEnabled() throws {
        guard ProcessInfo.processInfo.environment["SIGNOFF_RUN_LIVE_TESTS"] == "1" else {
            throw NSError(domain: "SignoffLiveTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Set SIGNOFF_RUN_LIVE_TESTS=1 to run live Foundation Models tests."])
        }
    }
    
    private func generateOne(bucket: String, recent: [String]) async -> String? {
        let result = await service.generate(
            bucketId: bucket,
            profile: nil,
            recentTexts: recent,
            unhingedLevel: bucket == "unhinged" ? .cynical : nil,
            toneValue: bucket == "professional" ? 0.5 : nil,
            postfixMode: .nothing,
            customInstructions: nil,
            phraseList: nil,
            ageGroup: .genZ,
            nsfwEnabled: false,
            bypassCache: true
        )
        if case .success(let outcome) = result {
            return outcome.text
        }
        return nil
    }

    @Test("Manual: Generate 50 Standard for review")
    func manualStandard() async throws {
        try requireLiveTestsEnabled()
        var recent: [String] = []
        var outputs: [String] = []
        
        for i in 1...50 {
            if let text = await generateOne(bucket: "standard", recent: recent) {
                outputs.append(text)
                recent.append(text)
                print("\(i). \(text)")
            } else {
                print("\(i). [FAILED]")
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        print("\n=== STANDARD \(outputs.count)/50 ===")
        print("Unique: \(Set(outputs).count)")
    }

    @Test("Manual: Generate 15 Professional for review")
    func manualProfessional() async throws {
        try requireLiveTestsEnabled()
        var recent: [String] = []
        var outputs: [String] = []
        
        for i in 1...15 {
            if let text = await generateOne(bucket: "professional", recent: recent) {
                outputs.append(text)
                recent.append(text)
                print("\(i). \(text)")
            } else {
                print("\(i). [FAILED]")
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        print("\n=== PROFESSIONAL \(outputs.count)/15 ===")
        print("Unique: \(Set(outputs).count)")
    }

    @Test("Manual: Generate 50 Unhinged for review")
    func manualUnhinged() async throws {
        try requireLiveTestsEnabled()
        var recent: [String] = []
        var outputs: [String] = []
        
        for i in 1...50 {
            if let text = await generateOne(bucket: "unhinged", recent: recent) {
                outputs.append(text)
                recent.append(text)
                print("\(i). \(text)")
            } else {
                print("\(i). [FAILED]")
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        
        print("\n=== UNHINGED \(outputs.count)/50 ===")
        print("Unique: \(Set(outputs).count)")
    }
}
