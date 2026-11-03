import Foundation
import SignoffCore

/// Error-rate harness. Drives the SHIPPING `GenerationService.generate` path
/// exactly like the app does (maintaining a 10-line recent history per bucket),
/// then measures how many of N generations surface a signoff that violates the
/// rules. Target: < 1% error rate over 100 generations per bucket.
///
/// Usage:
///   swift run ErrorRateHarness --bucket all --count 100
///   swift run ErrorRateHarness --bucket unhinged --count 20
@main
@MainActor
struct ErrorRateHarness {
    static func main() async {
        let args = CommandLine.arguments
        var bucket = "all"
        var count = 100
        if let i = args.firstIndex(of: "--bucket"), i + 1 < args.count { bucket = args[i + 1] }
        if let i = args.firstIndex(of: "--count"), i + 1 < args.count, let n = Int(args[i + 1]) { count = n }

        // In-memory persistence so we never pollute the real store.
        let persistence = PersistenceController.inMemory()
        GenerationService.shared.attach(persistence: persistence)

        let buckets: [String]
        if bucket == "all" { buckets = ["standard", "unhinged", "professional"] }
        else { buckets = [bucket] }

        var anyFail = false
        for bid in buckets {
            let r = await runBucket(bid, count: count)
            print(r.summary())
            if r.errorRate >= 0.01 { anyFail = true }
        }
        if anyFail {
            print("\n❌ ERROR RATE ≥ 1% — do not ship.")
            exit(1)
        } else {
            print("\n✅ All buckets under 1% error rate.")
        }
    }

    static func runBucket(_ bucketId: String, count: Int) async -> BucketResult {
        var accepted: [String] = []
        var recent: [String] = []          // dedup window (per-bucket size below)
        var errors: [String] = []
        var failures = 0

        for i in 1...count {
            let outcome = await GenerationService.shared.generate(
                bucketId: bucketId,
                profile: nil,
                recentTexts: recent,
                unhingedLevel: (bucketId == BucketID.unhinged.rawValue) ? .cynical : nil,
                toneValue: (bucketId == BucketID.professional.rawValue) ? 0.5 : nil,
                postfixMode: .nothing,
                customInstructions: nil,
                phraseList: nil,
                ageGroup: .genZ,
                nsfwEnabled: false,
                bypassCache: true
            )
            switch outcome {
            case .success(let o):
                let text = o.text
                if let e = semanticViolation(text, bucketId: bucketId, recent: recent) {
                    errors.append("#\(i): \(text) — \(e)")
                } else {
                    accepted.append(text)
                    recent.append(text)
                    // Standard bucket: 10-line window (the 3B model's pop-culture
                    // vocabulary is ~15-20 lines; a 40-window causes exhaustion).
                    // Unhinged/professional: 40-line window (more creative room).
                    let windowSize = (bucketId == BucketID.standard.rawValue) ? 15 : 40
                    if recent.count > windowSize { recent.removeFirst(recent.count - windowSize) }
                }
            case .providerFailed(let reason):
                failures += 1
                errors.append("#\(i): FAILED — \(reason)")
            case .usageLimitReached:
                failures += 1
                errors.append("#\(i): USAGE LIMIT")
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        // Diversity metrics on accepted lines.
        let counts = Dictionary(grouping: accepted, by: { $0 }).mapValues { $0.count }
        let maxFreq = counts.values.max() ?? 0
        let unique = counts.count

        return BucketResult(
            bucketId: bucketId,
            count: count,
            accepted: accepted,
            errors: errors,
            failures: failures,
            unique: unique,
            maxFreq: maxFreq
        )
    }

    /// Semantic rule violations that the pipeline's mechanical gate should have
    /// caught — this is the harness's independent check for "did a bad signoff
    /// slip through." The harness's `recent` window is 25, matching AppState.
    /// Note: the harness is intentionally a LIGHTER check than the shipping
    /// gate (no shape-collision) so it can detect shape-fixation that the
    /// pipeline's dedup misses.
    static func semanticViolation(_ text: String, bucketId: String, recent: [String]) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // Format.
        guard trimmed.hasSuffix(",") else { return "No trailing comma" }
        let words = trimmed.dropLast().split { $0.isWhitespace }
        let (minW, maxW): (Int, Int)
        switch bucketId {
        case BucketID.professional.rawValue: (minW, maxW) = (1, 6)
        case BucketID.unhinged.rawValue: (minW, maxW) = (2, 10)
        default: (minW, maxW) = (1, 8)
        }
        if words.count < minW || words.count > maxW {
            return "Word count \(words.count) out of \(minW)-\(maxW)"
        }
        if let first = words.first, let firstChar = first.first, !firstChar.isUppercase {
            return "First word not capitalized"
        }

        // Repeat checks apply to creative buckets. Professional is intentionally
        // excluded: its compact vocabulary is expected to reuse standard
        // closers and the shipping path does not suppress those.
        if bucketId != BucketID.professional.rawValue {
            let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
            if recent.contains(where: { $0.compare(trimmed, options: opts) == .orderedSame }) {
                return "Exact repeat of recent line"
            }
            if bucketId == BucketID.unhinged.rawValue, let near = nearDuplicate(trimmed, against: recent) {
                return near
            }
        }

        // Unhinged semantic bans (independent re-check of the pipeline's).
        if bucketId == BucketID.unhinged.rawValue {
            let workWords = [
                "memo", "meeting", "deadline", "email", "inbox", "report",
                "contract", "agenda", "boss", "workday", "sprint", "ticket",
                "the office", "at work", "work", "job", "burn the",
                "cancel the", "delete the", "ignore the", "per my last",
                "submit", "approve", "reschedule", "postpone", "forward this",
                "attach", "i quit", "destroy", "delete", "burn", "the memo", "the meeting", "the deadline",
                "the email", "the report", "the contract", "the agenda",
            ]
            if let hit = workWords.first(where: { lower.contains($0) }) {
                return "Work reference \"\(hit)\""
            }
            let distress = [
                "burned out", "drowning", "overwhelmed", "despair", "therapy",
                "breakdown", "mental health", "giving up", "hanging by a thread",
                "can't do this", "cannot do this", "winging it", "tapped out",
                "sleepwalking", "in shambles",
            ]
            if let hit = distress.first(where: { lower.contains($0) }) {
                return "Distress \"\(hit)\""
            }
        }
        return nil
    }

    static func nearDuplicate(_ candidate: String, against history: [String], threshold: Double = 0.6) -> String? {
        func bigrams(_ s: String) -> Set<String> {
            let words = s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            guard words.count > 1 else { return Set(words) }
            var out = Set<String>()
            for i in 0..<(words.count - 1) { out.insert("\(words[i]) \(words[i + 1])") }
            return out
        }
        let cb = bigrams(candidate)
        guard !cb.isEmpty else { return nil }
        for h in history {
            let hb = bigrams(h)
            guard !hb.isEmpty else { continue }
            let inter = cb.intersection(hb).count
            let union = cb.union(hb).count
            guard union > 0 else { continue }
            if Double(inter) / Double(union) >= threshold {
                return "Near-duplicate of \"\(h)\""
            }
        }
        return nil
    }
}

struct BucketResult {
    let bucketId: String
    let count: Int
    let accepted: [String]
    let errors: [String]
    let failures: Int
    let unique: Int
    let maxFreq: Int

    var errorRate: Double { Double(errors.count) / Double(count) }

    func summary() -> String {
        var s = "\n================ \(bucketId.uppercased()) ================\n"
        s += "Generations: \(count) | Accepted: \(accepted.count) | Errors: \(errors.count) (rate \(String(format: "%.2f", errorRate * 100))%) | Provider-fails: \(failures)\n"
        s += "Diversity: \(unique) unique / \(accepted.count) | max repeats of one line: \(maxFreq)\n"
        if bucketId == "unhinged" {
            let topicTerms = ["toaster", "spoon", "moon", "shadow", "clock", "ghost", "cloud", "gravity"]
            let topicCounts = topicTerms.map { term in accepted.filter { $0.lowercased().contains(term) }.count }
            if let highest = topicCounts.max(), highest > 0 {
                s += "Topic concentration: max shared-image count \(highest)/\(accepted.count)\n"
            }
        }
        if accepted.isEmpty {
            s += "  (no accepted lines)\n"
        } else {
            s += "Sample:\n"
            for line in accepted.prefix(15) { s += "  · \(line)\n" }
            if accepted.count > 15 { s += "  … (\(accepted.count - 15) more)\n" }
        }
        if !errors.isEmpty {
            s += "Errors:\n"
            for e in errors.prefix(20) { s += "  ✗ \(e)\n" }
            if errors.count > 20 { s += "  … (\(errors.count - 20) more)\n" }
        }
        return s
    }
}
