import Foundation
import SignoffCore

/// Provider bench. Drives ONE raw generation per sample per provider — no
/// retry loops, no validator gauntlet — so the outputs below are what each
/// model actually produces on a single roll. This is the honest A/B: the
/// shipping path currently uses fmf only; docs/CLOUD_PLAN.md decides whether
/// cloud becomes primary based on this data.
///
/// Usage:
///   swift run ProviderBench                                    # all buckets, all providers with keys
///   swift run ProviderBench --count 12 --bucket unhinged
///   swift run ProviderBench --providers openai,anthropic       # cloud-only
///
/// Keys: SIGNOFF_OPENAI_KEY / SIGNOFF_ANTHROPIC_KEY env vars, or Keychain
/// accounts `api.openai` / `api.anthropic`. Providers without a key are
/// reported as skipped, not failures.
@main
@MainActor
struct ProviderBench {
    static func main() async {
        var count = 8
        var buckets = ["standard", "professional", "unhinged"]
        var requestedProviders = ["fmf", "openai", "anthropic"]

        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--count"), i + 1 < args.count, let n = Int(args[i + 1]) { count = max(1, n) }
        if let i = args.firstIndex(of: "--bucket"), i + 1 < args.count { buckets = [args[i + 1]] }
        if let i = args.firstIndex(of: "--providers"), i + 1 < args.count {
            requestedProviders = args[i + 1].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }

        let providers = buildProviders(requested: requestedProviders)

        var report = "# Provider Bench — \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))\n\n"
        report += "Samples per bucket×provider: \(count) · single roll each, no retries, sanitized for format only.\n\n"

        var anyFailure = false
        for bucketId in buckets {
            for (id, provider) in providers {
                let r = await runCell(bucketId: bucketId, providerID: id, provider: provider, count: count)
                print(r.summary())
                report += r.markdown()
                if !r.failures.isEmpty { anyFailure = true }
            }
        }

        let fileURL = URL(fileURLWithPath: "bench_results.md")
        try? report.write(to: fileURL, atomically: true, encoding: .utf8)
        print("\n📝 Full report written to \(fileURL.path)")

        // A cell failing entirely (e.g. no key) is expected and fine; we only
        // exit nonzero if EVERYTHING failed, which means the bench itself broke.
        if providers.isEmpty || (anyFailure && providers.count == 1 && providers[0].0 == "fmf" && allCellsFailed) {
            print("\n❌ Bench could not run — no provider produced any result.")
            exit(1)
        }
    }

    static var allCellsFailed = false

    /// Builds the provider list, skipping cloud providers whose keys are absent.
    static func buildProviders(requested: [String]) -> [(String, any GenerationProvider)] {
        var out: [(String, any GenerationProvider)] = []
        for id in requested {
            switch id {
            case "fmf":
                out.append(("fmf", FoundationModelsProvider()))
            case "openai":
                do {
                    _ = try CloudKeyStore.openAIKey()
                    out.append(("openai", OpenAIProvider()))
                } catch {
                    print("⏭️  Skipping openai: \(error.localizedDescription)")
                }
            case "anthropic":
                do {
                    _ = try CloudKeyStore.anthropicKey()
                    out.append(("anthropic", AnthropicProvider()))
                } catch {
                    print("⏭️  Skipping anthropic: \(error.localizedDescription)")
                }
            default:
                print("⏭️  Unknown provider '\(id)'")
            }
        }
        return out
    }

    /// Runs `count` generations for one bucket×provider cell, maintaining
    /// rolling history so later samples face the same conditions as the app.
    static func runCell(bucketId: String, providerID: String, provider: any GenerationProvider, count: Int) async -> CellResult {
        var accepted: [String] = []
        var failures: [(String, String)] = []   // (reason, detail)
        var latencies: [Int] = []

        // Cloud arms mirror the future cloud-primary shipping path: real
        // web-harvested style anchors instead of the static bank. Skipped
        // silently when no Exa key is present (bench still runs).
        var freshExamples: [String] = []
        if providerID != "fmf", bucketId != BucketID.professional.rawValue {
            freshExamples = await FreshExamplesService.shared.currentExamples()
            if !freshExamples.isEmpty {
                print("  [\(bucketId)/\(providerID)] using \(freshExamples.count) fresh web-harvested anchors")
            }
        }

        let service = GenerationService()
        for i in 1...count {
            do {
                let template = await PromptTemplate.load(bucket: bucketId) ?? .fallback
                let unhingedLevel: UnhingedLevel? = (bucketId == BucketID.unhinged.rawValue) ? .cynical : nil
                let toneValue: Double? = (bucketId == BucketID.professional.rawValue) ? 0.5 : nil

                if providerID == "fmf" {
                    let outcome = await service.generate(
                        bucketId: bucketId, profile: nil, recentTexts: accepted,
                        unhingedLevel: unhingedLevel, toneValue: toneValue,
                        postfixMode: .nothing)
                    switch outcome {
                    case .success(let generated):
                        accepted.append(generated.text)
                        latencies.append(generated.latencyMs)
                        print("  [\(bucketId)/\(providerID)] #\(i) (\(generated.latencyMs)ms) \(generated.text)")
                    case .providerFailed(let reason):
                        failures.append((reason, ""))
                        print("  [\(bucketId)/\(providerID)] #\(i) FAILED — \(reason)")
                    case .usageLimitReached:
                        failures.append(("Usage limit reached", ""))
                        print("  [\(bucketId)/\(providerID)] #\(i) FAILED — Usage limit reached")
                    }
                    continue
                }

                var composed = PromptComposer.compose(
                    template: template,
                    profile: UserProfileSnapshot(),
                    recentTexts: accepted,
                    unhingedLevel: unhingedLevel,
                    toneValue: toneValue,
                    postfixMode: .nothing,
                    attempt: 1,
                    curatedExamples: freshExamples,
                    bucketId: bucketId)

                // Cloud models handle explicit avoid lists fine (the
                // "pink-elephant" copying failure is 3B-specific). Rolling
                // history is how the 50-emails-a-day user stays repetition-
                // free without any hardcoded corpus — so prove it here.
                if providerID != "fmf", bucketId != BucketID.professional.rawValue, !accepted.isEmpty {
                    let window = accepted.suffix(30).map { "- \($0)" }.joined(separator: "\n")
                    composed = PromptComposer.Composed(
                        instructions: composed.instructions,
                        prompt: composed.prompt
                            + "\n\nRecent lines you already produced for this user — do NOT repeat them or trivial variants:\n"
                            + window,
                        promptPrefix: composed.promptPrefix)
                }

                let context = ProviderGenerateContext(
                    bucketId: bucketId, template: template, composed: composed,
                    unhingedLevel: unhingedLevel, toneValue: toneValue)

                let t0 = Date()
                let raw = try await provider.generate(context)
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                latencies.append(ms)

                // Light validation: format sanitize + length. No banned-word
                // graveyard — judge the model, not the scaffolding.
                let sanitized = ProviderResponseGuard.sanitizeSignoff(raw, bucketId: bucketId)
                let final = try ProviderResponseGuard.validatedPasteable(sanitized, provider: providerID)
                accepted.append(final)
                print("  [\(bucketId)/\(providerID)] #\(i) (\(ms)ms) \(final)")
            } catch {
                failures.append((error.localizedDescription, ""))
                print("  [\(bucketId)/\(providerID)] #\(i) FAILED — \(error.localizedDescription)")
            }
        }

        let avg = latencies.isEmpty ? 0 : latencies.reduce(0, +) / latencies.count
        let unique = Set(accepted.map { $0.lowercased() }).count
        return CellResult(bucketId: bucketId, providerID: providerID, accepted: accepted,
                          unique: unique, avgLatencyMs: avg, failures: failures.map { $0.0 })
    }
}

struct CellResult {
    let bucketId: String
    let providerID: String
    let accepted: [String]
    let unique: Int
    let avgLatencyMs: Int
    let failures: [String]

    func summary() -> String {
        var s = "\n=== [\(bucketId) / \(providerID)] accepted \(accepted.count) · unique \(unique)/\(accepted.count) · avg \(avgLatencyMs)ms · failed \(failures.count) ===\n"
        for line in accepted { s += "  · \(line)\n" }
        return s
    }

    func markdown() -> String {
        var s = "## \(bucketId) / \(providerID)\n\n"
        s += "accepted \(accepted.count)/\(accepted.count + failures.count) · unique \(unique) · avg latency \(avgLatencyMs)ms\n\n"
        for line in accepted { s += "- \(line)\n" }
        if !failures.isEmpty {
            s += "\nFailures:\n"
            for f in failures { s += "- \(f)\n" }
        }
        s += "\n"
        return s
    }
}
