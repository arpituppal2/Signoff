import Foundation
import SignoffCore

@main
struct TestProfessional {
    static func main() async {
        setbuf(stdout, nil)
        print("=== Testing Professional Bucket ===")
        let service = GenerationService.shared
        await service.warmup()
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        print("\n--- 5 Professional Generations ---")
        for i in 1...5 {
            let outcome = await service.generate(
                bucketId: "professional",
                profile: nil,
                recentTexts: [],
                unhingedLevel: nil,
                toneValue: nil,
                postfixMode: .nothing,
                customInstructions: nil,
                phraseList: nil,
                ageGroup: .genZ,
                nsfwEnabled: false,
                bypassCache: true
            )

            switch outcome {
            case .success(let result):
                print("\(i). '\(result.text)'")
            case .providerFailed(let reason):
                print("\(i). FAILED: \(reason)")
            case .usageLimitReached:
                print("\(i). USAGE LIMIT REACHED")
            }

            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }
}