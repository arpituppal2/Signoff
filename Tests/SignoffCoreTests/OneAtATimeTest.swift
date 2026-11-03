import Testing
import Foundation
@testable import SignoffCore

@MainActor
@Suite(.serialized)
struct OneAtATimeTest {

    private let service = GenerationService.shared

    private func generateOne(bucket: String, recent: [String], tone: Double? = nil, unhingedLevel: UnhingedLevel? = nil) async -> String? {
        let result = await service.generate(
            bucketId: bucket,
            profile: nil,
            recentTexts: recent,
            unhingedLevel: unhingedLevel,
            toneValue: tone,
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

    @Test("One at a time: Quotes bucket (50)")
    func oneAtATimeQuotes() async throws {
        var recent: [String] = []
        var outputs: [String] = []

        // Warmup
        await service.warmup()
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        print("=== QUOTES: 50 signoffs one at a time ===")

        for i in 1...50 {
            var text: String?
            for attempt in 1...5 {
                text = await generateOne(bucket: "quotes", recent: recent)
                if text != nil { break }
                print("  [retry \(attempt)]")
                try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt))) * 1_000_000_000)
            }

            if let t = text {
                recent.append(t)
                outputs.append(t)
                print("\(i). \(t)")
            } else {
                print("\(i). [FAILED]")
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        // Summary
        let unique = Set(outputs).count
        print("\n=== QUOTES SUMMARY ===")
        print("Total: \(outputs.count)")
        print("Unique: \(unique)")
    }

    @Test("One at a time: Professional bucket (15)")
    func oneAtATimeProfessional() async throws {
        var recent: [String] = []
        var outputs: [String] = []

        // Warmup
        await service.warmup()
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        print("=== PROFESSIONAL: 15 signoffs one at a time ===")

        for i in 1...15 {
            var text: String?
            for attempt in 1...5 {
                text = await generateOne(bucket: "professional", recent: recent)
                if text != nil { break }
                print("  [retry \(attempt)]")
                try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt))) * 1_000_000_000)
            }

            if let t = text {
                recent.append(t)
                outputs.append(t)
                print("\(i). \(t)")
            } else {
                print("\(i). [FAILED]")
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        // Summary
        let unique = Set(outputs).count
        print("\n=== PROFESSIONAL SUMMARY ===")
        print("Total: \(outputs.count)")
        print("Unique: \(unique)")
    }

    @Test("One at a time: Unhinged bucket (50)")
    func oneAtATimeUnhinged() async throws {
        var recent: [String] = []
        var outputs: [String] = []

        // Warmup
        await service.warmup()
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        print("=== UNHINGED: 50 signoffs one at a time ===")

        for i in 1...50 {
            var text: String?
            for attempt in 1...5 {
                text = await generateOne(bucket: "unhinged", recent: recent, unhingedLevel: .cynical)
                if text != nil { break }
                print("  [retry \(attempt)]")
                try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt))) * 1_000_000_000)
            }

            if let t = text {
                recent.append(t)
                outputs.append(t)
                print("\(i). \(t)")
            } else {
                print("\(i). [FAILED]")
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        // Summary
        let unique = Set(outputs).count
        print("\n=== UNHINGED SUMMARY ===")
        print("Total: \(outputs.count)")
        print("Unique: \(unique)")
    }
}
