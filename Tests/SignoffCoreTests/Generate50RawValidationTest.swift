import Testing
import Foundation
@testable import SignoffCore

@MainActor
struct Generate50RawValidationTest {

    @Test("Generate 50 raw signoffs per bucket (using generateRaw) and validate")
    func generate50RawValidation() async throws {
        try requireLiveTestsEnabled()
        let service = GenerationService.shared
        // Validator deleted per user request — generation-only collection now.

        // Warm up
        print("Warming up Foundation Models...")
        await service.warmup()

        let buckets = ["standard", "professional", "unhinged"]

        for bucket in buckets {
            print("\n\n=== PROCESSING BUCKET: \(bucket) ===")

            var history: [String] = [] // recentTexts for generateRaw
            var results: [String] = []
            var attempts = 0
            let maxAttemptsPerSignoff = 5 // To avoid infinite loops

            while results.count < 50 && attempts < 50 * maxAttemptsPerSignoff {
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
                    recentTexts: [],
                    toneValue: nil,
                    postfixMode: .nothing,
                    customInstructions: nil,
                    phraseList: nil,
                    ageGroup: .genZ,
                    preferredRegister: nil
                )

                switch outcome {
                case .success(let outcome):
                    let text = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    print("\(String(format: "%2d", results.count + 1)): Generated: '\(text)'")

                    // Add to history and results
                    history.append(text)
                    results.append(text)

                    // Keep history at a reasonable size (last 60 as in the one-by-one test)
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
            print("Generated \(results.count)/50 signoffs after \(attempts) attempts")

            if results.isEmpty {
                print("No signoffs generated.")
                continue
            }

            // Now validate the results
            var validatorFailures: [String] = []
            var terminusFailures: [String] = []

            for r in results {
                // Validator deleted per user request — generation-only harness now.
                if !hasCleanTerminus(r) {
                    terminusFailures.append(r)
                }
            }

            // Shape diversity (redundancy test)
            let patternPass = shapeDiversityPass(results)

            // Uniqueness
            let uniqueCount = Set(results).count

            print("\n--- VALIDATION ---")
            print("Validator failures: \(validatorFailures.count)")
            if !validatorFailures.isEmpty {
                for failure in validatorFailures.prefix(5) {
                    print("  \(failure)")
                }
                if validatorFailures.count > 5 {
                    print("  ... and \(validatorFailures.count - 5) more")
                }
            }
            print("Terminus failures: \(terminusFailures.count)")
            if !terminusFailures.isEmpty {
                for failure in terminusFailures.prefix(5) {
                    print("  \(failure)")
                }
                if terminusFailures.count > 5 {
                    print("  ... and \(terminusFailures.count - 5) more")
                }
            }
            print("Shape diversity pass: \(patternPass)")
            print("Unique signoffs: \(uniqueCount)/\(results.count)")

            // Summary
            let passedCount = results.count - validatorFailures.count
            print("\n--- SUMMARY ---")
            print("Total generated: \(results.count)")
            print("Passed validation: \(passedCount) (\(String(format: "%.1f", Double(passedCount)/Double(results.count)*100))%)")
            print("Passed terminus: \(results.count - terminusFailures.count) (\(String(format: "%.1f", Double(results.count - terminusFailures.count)/Double(results.count)*100))%)")
            print("Unique: \(uniqueCount) (\(String(format: "%.1f", Double(uniqueCount)/Double(results.count)*100))%)")
            print("Shape diversity: \(patternPass ? "PASS" : "FAIL")")

            // Assertions (adjust per bucket)
            switch bucket {
            case "standard":
                #expect(results.count >= 40, "Standard bucket should generate at least 40 raw signoffs (got \(results.count))")
                #expect(validatorFailures.count <= 10, "Too many validator failures for standard: \(validatorFailures.count)")
                #expect(terminusFailures.count <= 5, "Too many terminus failures for standard: \(terminusFailures.count)")
                #expect(shapeDiversityPass(results), "Standard bucket redundancy test failed")
                #expect(uniqueCount >= 15, "Standard bucket too few unique signoffs: \(uniqueCount)/50")
            case "professional":
                #expect(results.count >= 12, "Professional bucket should generate at least 12 raw signoffs (got \(results.count))")
                #expect(validatorFailures.count <= 5, "Too many validator failures for professional: \(validatorFailures.count)")
                #expect(terminusFailures.count <= 5, "Too many terminus failures for professional: \(terminusFailures.count)")
                let minUnique = 6
                #expect(uniqueCount >= minUnique, "Professional bucket too few unique signoffs: \(uniqueCount)/\(results.count)")
            case "unhinged":
                #expect(results.count >= 40, "Unhinged bucket should generate at least 40 raw signoffs (got \(results.count))")
                #expect(validatorFailures.count <= 10, "Too many validator failures for unhinged: \(validatorFailures.count)")
                #expect(terminusFailures.count <= 5, "Too many terminus failures for unhinged: \(terminusFailures.count)")
                #expect(shapeDiversityPass(results), "Unhinged bucket redundancy test failed")
                #expect(uniqueCount >= 15, "Unhinged bucket too few unique signoffs: \(uniqueCount)/50")
            default:
                break
            }
        }
    }

    private func requireLiveTestsEnabled() throws {
        guard ProcessInfo.processInfo.environment["SIGNOFF_RUN_LIVE_TESTS"] == "1" else {
            throw NSError(domain: "SignoffLiveTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Set SIGNOFF_RUN_LIVE_TESTS=1 to run live Foundation Models tests."])
        }
    }

    private func hasCleanTerminus(_ s: String) -> Bool {
        guard let last = s.last else { return false }
        return last == "," || last == "." || last.isLetter
    }

    private func shapeDiversityPass(_ results: [String]) -> Bool {
        var patternCounts: [String: Int] = [:]
        for r in results {
            let tokens = r.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            let pattern: String
            if tokens.count >= 3 {
                pattern = "\(tokens[0]) \(tokens[1]) …"
            } else {
                pattern = r.lowercased()
            }
            patternCounts[pattern, default: 0] += 1
        }
        let maxAllowed = Int(Double(results.count) * 0.25) + 1
        for (pattern, count) in patternCounts {
            if count > maxAllowed {
                print("SHAPE DIVERSITY FAIL: pattern '\(pattern)' appears \(count) times (max \(maxAllowed))")
                return false
            }
        }
        return true
    }
}