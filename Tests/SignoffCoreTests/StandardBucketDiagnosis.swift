import Testing
import Foundation
@testable import SignoffCore

/// Diagnose why the standard bucket is failing in batch generation.
/// We'll run the same logic as generateBucket but with detailed logging.
@MainActor
@Suite(.serialized)
struct StandardBucketDiagnosis {
    private let service = GenerationService.shared
    // private let validator = SignoffQualityValidator.shared   // deleted per user request

    @Test("Diagnose Standard bucket: log each attempt and validation failure reason")
    func diagnoseStandardBucket() async throws {
        let bucketId = "standard"
        let count = 20  // We'll diagnose 20 attempts
        let maxRetries = 3

        print("\n=== DIAGNOSING STANDARD BUCKET (first \(count) attempts) ===")

        var results: [String] = []

        for i in 1...count {
            let fmReady = service.isFoundationModelsReady()
            print("[DIAG] \(bucketId) Iteration \(i)/\(count): fmReady=\(fmReady)")

            if !fmReady {
                print("[DIAG] Foundation Models not ready, stopping")
                break
            }

            var outcomeText: String?
            var attemptDetails: [(attempt: Int, text: String?, validationReason: String?)] = []

            for attempt in 1...maxRetries {
                // Invalidate session pool before each attempt
                if #available(macOS 26, *) {
                    await FoundationModelsSessionPool.shared.invalidateAll()
                }
                let result = await service.generate(
                    bucketId: bucketId,
                    profile: nil,
                    recentTexts: results,
                    toneValue: nil,
                    postfixMode: .nothing,
                    customInstructions: nil,
                    phraseList: nil,
                    ageGroup: .genZ,
                    nsfwEnabled: false,
                    bypassCache: true
                )

                if case .success(let outcome) = result {
                    outcomeText = outcome.text
                    attemptDetails.append((attempt, outcome.text, nil))
                    break
                } else if case .providerFailed(let reason) = result {
                    attemptDetails.append((attempt, nil, "provider failed: \(reason)"))
                    if attempt < maxRetries {
                        let delay = UInt64(pow(2.0, Double(attempt + 1))) * 1_000_000_000
                        print("[DIAG] \(bucketId) Iteration \(i) attempt \(attempt) failed, retrying in \(delay/1_000_000_000)s...")
                        try? await Task.sleep(nanoseconds: delay)
                        if #available(macOS 26, *) {
                            await FoundationModelsSessionPool.shared.invalidateAll()
                        }
                    }
                } else if case .usageLimitReached = result {
                    attemptDetails.append((attempt, nil, "usage limit reached"))
                    break
                }
            }

            if let text = outcomeText {
                results.append(text)
                print("[DIAG] \(bucketId) Iteration \(i): SUCCESS -> '\(text)'")
                // Show validation attempts
                for (attempt, attemptedText, reason) in attemptDetails {
                    if let attemptedText = attemptedText {
                        print("[DIAG]   Attempt \(attempt): '\(attemptedText)' -> \(reason ?? "VALID")")
                    } else {
                        print("[DIAG]   Attempt \(attempt): FAILED -> \(reason ?? "unknown")")
                    }
                }
            } else {
                print("[DIAG] \(bucketId) Iteration \(i): FAILED ALL \(maxRetries) ATTEMPTS")
                for (attempt, attemptedText, reason) in attemptDetails {
                    if let attemptedText = attemptedText {
                        print("[DIAG]   Attempt \(attempt): '\(attemptedText)' -> \(reason ?? "VALID")")
                    } else {
                        print("[DIAG]   Attempt \(attempt): FAILED -> \(reason ?? "unknown")")
                    }
                }
            }

            // Small delay between generations
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        print("\n=== FINAL RESULTS ===")
        print("Successful generations: \(results.count)/\(count)")

        if !results.isEmpty {
            print("\nSuccessful signoffs:")
            for (i, result) in results.enumerated() {
                print("\(i+1). \(result)")
            }
        }

        // Now validate all successful results against the full history (as the batch test does)
        print("\n=== VALIDATING AGAINST FULL HISTORY (batch test style) ===")
        var validatorFailures: [String] = []
        var terminusFailures: [String] = []

        for r in results {
            // Validator deleted per user request — diagnosis is generation-only now.
            _ = r // keep loop for future terminal/shape checks
            // Terminus check (clean ending)
            guard let last = r.last else { continue }
            if !(last == "," || last == "." || last.isLetter) {
                terminusFailures.append(r)
            }
        }

        print("Validator failures: \(validatorFailures.count)")
        if !validatorFailures.isEmpty {
            for failure in validatorFailures {
                print("  \(failure)")
            }
        }
        print("Terminus failures: \(terminusFailures.count)")
        if !terminusFailures.isEmpty {
            for failure in terminusFailures {
                print("  \(failure)")
            }
        }

        // Redundancy test (shape diversity)
        let patternPass = shapeDiversityPass(results)
        print("Shape diversity (redundancy test) pass: \(patternPass)")
        if !patternPass {
            print("  -> Redundancy test failed")
        }

        // Uniqueness
        let uniqueCount = Set(results).count
        print("Unique signoffs: \(uniqueCount)/\(results.count)")
        let minUnique = 15  // As in batch test
        print("Minimum unique required: \(minUnique)")
        if uniqueCount < minUnique {
            print("  -> UNIQUENESS TEST FAILED")
        }
    }

    /// Redundancy Test: no more than 25% of outputs may share one syntactic pattern.
    /// Pattern = first 2 tokens (opening bigram) for lines >=3 tokens, or full line for shorter.
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