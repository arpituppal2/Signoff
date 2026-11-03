import Foundation

/// Single source of truth for generation-pipeline tuning. Every retry budget,
/// dedup depth, and sampling knob lives here — no magic numbers scattered
/// through GenerationService / PromptComposer / Providers.
///
/// Rationale for the current values (measured on-device, 3B Foundation Models):
/// - Retry budgets are sized to the per-attempt acceptance odds observed in
///   burst harness runs; too small = exhaustion errors, too big = latency.
/// - Dedup depths approximate each bucket's diversity ceiling: pushing past
///   what the model can produce fresh guarantees exhaustion.
public enum GenerationTuning {

    // MARK: Retry budgets (outer loop, executeHybridGeneration)

    /// FM is the OFFLINE FALLBACK now (cloud primary) — a bounded roll count
    /// per generation keeps fallback latency sane. Standard and professional
    /// converge fast (closed vocabularies). Unhinged needs more: the on-device
    /// 3B fixates in bursts (a "toaster mood" that produces the same fixated
    /// object across every register), and each roll re-sends different few-shots
    /// via register cycling, so more rolls = more chances the mood shifts. 10
    /// (up from 6) breaks a typical fixation burst while capping worst-case
    /// latency at ~2s on-device; observed exhaustion at 6 was 2-in-10 runs.
    public static let maxAttemptsStandard: Int = 6
    public static let maxAttemptsProfessional: Int = 6
    public static let maxAttemptsUnhinged: Int = 10
    public static let maxAttemptsDefault: Int = 6

    /// Cloud path (OpenAI → Anthropic walk): frontier models rarely need more
    /// than one roll; 2 per provider bounds worst-case latency before the FM
    /// fallback takes over.
    public static let maxAttemptsPerCloudProvider: Int = 2

    public static func maxAttempts(bucketId: String) -> Int {
        switch bucketId {
        case BucketID.standard.rawValue: return maxAttemptsStandard
        case BucketID.professional.rawValue: return maxAttemptsProfessional
        case BucketID.unhinged.rawValue: return maxAttemptsUnhinged
        default: return maxAttemptsDefault
        }
    }

    // MARK: Dedup windows (lines of accepted history checked post-generation)

    /// ≈ the 3B model's real-quote recall span (~15-20 lines); deeper windows
    /// guarantee exhaustion once the fresh-quote pool is spent.
    public static let dedupDepthStandard: Int = 14
    /// Feeds exact-dedup AND the repeat-family noun gate. Humans legitimately
    /// reuse closer families across emails; only near-adjacent repeats read as
    /// robotic.
    public static let dedupDepthProfessional: Int = 6
    public static let dedupDepthUnhinged: Int = 40

    public static func dedupDepth(bucketId: String) -> Int {
        switch bucketId {
        case BucketID.standard.rawValue: return dedupDepthStandard
        case BucketID.professional.rawValue: return dedupDepthProfessional
        case BucketID.unhinged.rawValue: return dedupDepthUnhinged
        default: return dedupDepthUnhinged
        }
    }

    /// Professional exact-match window: only immediate neighbors block an
    /// identical re-serve ("Regards," twice in one burst is fine at distance).
    public static let professionalExactDedupDepth: Int = 2

    /// How many recent lines the noun-repeat-family gate scans.
    public static let professionalFamilyGateDepth: Int = 6

    /// How many recent accepted lines the unhinged shape-collision memory
    /// compares against. Intentionally short (~15) so it catches back-to-back
    /// opener-reuse ("All fax," → "All toast,") without starving the retry
    /// budget against the full 40-line dedup window — a line that resembles
    /// one from 30 generations ago is fine, the user never sees them adjacent.
    public static let shapeCollisionWindow: Int = 15

    // MARK: Sampling temperatures

    public static let temperatureProfessional: Double = 0.55
    public static let temperatureUnhinged: Double = 0.68
    public static let temperatureStandard: Double = 0.55
    public static let temperatureDefault: Double = 0.65

    public static func temperature(bucketId: String) -> Double {
        switch bucketId {
        case "professional": return temperatureProfessional
        case "unhinged": return temperatureUnhinged
        case "standard": return temperatureStandard
        default: return temperatureDefault
        }
    }

    // MARK: Prompt composition sizes

    /// Few-shot examples shown from the selected register.
    public static let fewShotExampleCount: Int = 5
    /// Recent closers named on the prompt-side avoid-list for professional
    /// (closed vocabulary — naming them redirects sampling safely).
    public static let professionalAvoidListDepth: Int = 8
}
