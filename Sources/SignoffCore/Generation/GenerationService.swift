import Foundation
import os
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The single entry point for generation. **On-device only.**
///
/// Hybrid strategy:
/// 1. Live Foundation Models generation with bucket-specific prompts and register few-shot examples
/// 2. Local SignoffQualityValidator filters output (banned tokens, similarity, length, narration, format)
/// 3. Up to 4 corrective retries with register-cycling for shape diversity
/// 4. Honest failure if no attempt passes — NEVER a hardcoded fallback signoff
@MainActor
public final class GenerationService: ObservableObject {
    public static let shared = GenerationService()

    private static let log = Logger(subsystem: "com.signoff", category: "GenerationService")

    @Published public private(set) var lastResult: GenerationOutcome?
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var lastStatus: GenerationStatusNotice?
    /// Published so the popover can show tier/usage status.
    @Published public private(set) var usageLimitReached: Bool = false

    private var inflightRequest: Bool = false

    /// Track used mechanisms per bucket for diversity
    private var usedMechanisms: [String: [String]] = [:]

    public init() {}

    public func clearStatus() {
        lastStatus = nil
    }

    public struct GenerationOutcome: Sendable, Equatable {
        public let text: String
        public let providerKind: GenerationProviderKind
        public let latencyMs: Int
        public let bucketId: String
        public let tone: String?
    }

    public enum Outcome: Sendable, Equatable {
        case success(GenerationOutcome)
        case providerFailed(reason: String)
        case usageLimitReached
    }

    public weak var persistence: PersistenceController?

    public func attach(persistence: PersistenceController) {
        self.persistence = persistence
    }

    public func generate(bucketId: String,
                         profile: UserProfile?,
                         recentTexts: [String],
                         unhingedLevel: UnhingedLevel? = nil,
                         toneValue: Double? = nil,
                         postfixMode: BucketPostfixMode = .nothing,
                         customInstructions: String? = nil,
                         phraseList: String? = nil,
                         ageGroup: AgeGroup? = nil,
                         nsfwEnabled: Bool = false,
                         bypassCache: Bool = false) async -> Outcome {
        let signpostID = SignoffSignpost.generateProvider.makeSignpostID()
        let state = SignoffSignpost.generateProvider.beginInterval(
            "generate", id: signpostID, "bucket: \(bucketId, privacy: .public)")
        defer { SignoffSignpost.generateProvider.endInterval("generate", state) }

        if inflightRequest {
            return .providerFailed(reason: "Generation already in progress")
        }

        // No usage limit — Signoff is free. All generations are allowed.

        inflightRequest = true
        defer { inflightRequest = false }
        isRunning = true
        defer { isRunning = false }

        let t0 = Date()
        return await runGeneration(
            bucketId: bucketId, profile: profile, recentTexts: recentTexts,
            unhingedLevel: unhingedLevel, toneValue: toneValue,
            postfixMode: postfixMode, customInstructions: customInstructions,
            phraseList: phraseList, ageGroup: ageGroup, nsfwEnabled: nsfwEnabled,
            t0: t0, bypassCache: bypassCache)
    }

    private func runGeneration(bucketId: String,
                               profile: UserProfile?,
                               recentTexts: [String],
                               unhingedLevel: UnhingedLevel?,
                               toneValue: Double?,
                               postfixMode: BucketPostfixMode,
                               customInstructions: String?,
                               phraseList: String?,
                               ageGroup: AgeGroup?,
                               nsfwEnabled: Bool,
                               t0: Date,
                               bypassCache: Bool = false) async -> Outcome {
        Self.log.info("[GenerationService] runGeneration: bucketId=\(bucketId, privacy: .public)")
        let snapshot = UserProfileSnapshot(profile: profile)
        let template = await PromptTemplate.load(bucket: bucketId) ?? .fallback
        Self.log.info("[GenerationService] runGeneration: loaded template for \(bucketId, privacy: .public), system.prefix=\(template.system.prefix(60), privacy: .public), userVariants=\(template.userVariants.count, privacy: .public)")
        let voice = ageGroup ?? .genZ

        // Get the voice profile for discriminative prompting
        let voiceProfile = VoiceProfile.shared

        // ── Live generation every time ──
        // The pre-warm cache has been removed by user request: every generate
        // is a live on-device Apple Foundation Models call. No cache hit path,
        // no background refill — the model runs on each use so output varies
        // and the generation is genuinely fresh every single time.
        BucketCache.shared.clearAll()

        // ── Hybrid: Live FMF → Validate → Retry (corrective, bounded) → Honest failure ──
        if foundationModelsIsReady() {
            GenerationDebugProbe.shared.setModelActive(true)
            GenerationDebugProbe.shared.recordEvent("live fmf start \(bucketId)")
            return await executeHybridGeneration(
                bucketId: bucketId, snapshot: snapshot, template: template,
                recentTexts: recentTexts, unhingedLevel: unhingedLevel,
                toneValue: toneValue, postfixMode: postfixMode,
                customInstructions: customInstructions, phraseList: phraseList,
                nsfwEnabled: nsfwEnabled,
                voice: voice, t0: t0,
                voiceProfile: voiceProfile, bypassCache: bypassCache)
        }

        // On-device model not ready — fail honestly. Per the user's hard rule,
        // a signoff is ALWAYS generated or the app fails gracefully. We never
        // surface a hand-coded corpus line as a fake signoff.
        let status = FoundationModelsAvailability.probe()
        GenerationDebugProbe.shared.setModelActive(false)
        GenerationDebugProbe.shared.recordEvent("model not ready: \(status.titleForFailure)")
        self.lastStatus = .foundationModelsUnavailable(used: .foundationModels)
        return .providerFailed(reason: FoundationModelsAvailability.userFacingCause(for: status))
    }

    /// Hybrid generation pipeline: Live FMF → Validate → Retry (corrective, register-cycling, bounded) → Honest failure.
    private func executeHybridGeneration(bucketId: String,
                                         snapshot: UserProfileSnapshot,
                                         template: PromptTemplate,
                                         recentTexts: [String],
                                         unhingedLevel: UnhingedLevel?,
                                         toneValue: Double?,
                                         postfixMode: BucketPostfixMode,
                                         customInstructions: String?,
                                         phraseList: String?,
                                         nsfwEnabled: Bool,
                                         voice: AgeGroup,
                                         t0: Date,
                                         voiceProfile: VoiceProfile,
                                         bypassCache: Bool = false) async -> Outcome {

        let validator = SignoffQualityValidator.shared
        let voiceSnapshot = PromptComposer.VoiceProfileSnapshot(from: voiceProfile)

        // Track used mechanisms for diversity
        let existingMechanisms = usedMechanisms[bucketId] ?? []
        let registers = template.registers ?? []

        // AppState predictive preference (from favorites history). Attempt 1
        // respects it; later attempts cycle registers for shape diversity.
        let preferredRegister = AppState.shared.preferredRegister(forBucket: bucketId)

        // Bounded generation-only retries. No hardcoded fallback — per the
        // user's hard rule a signoff is ALWAYS generated or the app fails
        // gracefully. We never surface a hand-coded corpus line as a signoff.
        // 12 attempts: the on-device 3B model fixates on opener patterns
        // ("Deadlines -ing," / "Officially X") and the validator's 12-window
        // avoid-list creates late-batch pressure — around iteration 8-10 of a
        // rapid burst, many candidates collide with the recent window and a
        // single generation needs more rolls to break free. 12 (vs the prior 8)
        // roughly doubles the chance of finding a clean candidate under pressure
        // (0.3^12 ≈ 5e-7 all-fail at 70% per-attempt odds) while staying
        // within a single-digit-second latency budget on-device. This is the
        // lever that moves the error-rate bar without tightening the
        // validator (which trades against yield and was WORSE per diag4/5).
        let maxAttempts = 12

        for attempt in 1...maxAttempts {
            if #available(macOS 26, *) {
                await MainActor.run { FoundationModelsAvailability.shared.refresh() }
                let fmfStatus = FoundationModelsAvailability.probe()
                guard case .available = fmfStatus else {
                    return .providerFailed(
                        reason: FoundationModelsAvailability.userFacingCause(for: fmfStatus))
                }

                let fmfID = SignoffSignpost.generateProvider.makeSignpostID()
                let fmfState = SignoffSignpost.generateProvider.beginInterval("fmf", id: fmfID)
                defer { SignoffSignpost.generateProvider.endInterval("fmf", fmfState) }

                do {
                    // Live generation uses ONLY the register few-shot examples
                    // baked into the prompt template. We deliberately do NOT
                    // inject random corpus entries — the corpus skews toward a
                    // single tired/caffeine theme and would recollapse
                    // generation toward "exhausted worker."

                    // Force register diversity on retries. Attempt 1 respects
                    // the AppState predictive preference; attempts 2+ cycle
                    // through the register list so the model isn't sent the
                    // same feeling twice in a row — this escapes validator-
                    // rejected ruts faster than re-rolling the same register,
                    // and every attempt sees a different few-shot set.
                    let forcedRegister: String?
                    if attempt == 1 {
                        forcedRegister = preferredRegister
                    } else if !registers.isEmpty {
                        forcedRegister = registers[(attempt - 2) % registers.count].name
                    } else {
                        forcedRegister = nil
                    }

                    let composed = PromptComposer.compose(
                        template: template, profile: snapshot, recentTexts: recentTexts,
                        unhingedLevel: unhingedLevel, toneValue: toneValue, postfixMode: postfixMode,
                        customInstructions: customInstructions, phraseList: phraseList,
                        ageGroup: voice,
                        voiceProfile: voiceSnapshot,
                        nsfwEnabled: nsfwEnabled,
                        attempt: attempt,
                        usedMechanisms: existingMechanisms,
                        curatedExamples: [],
                        preferredRegister: forcedRegister)

                    let context = ProviderGenerateContext(
                        bucketId: bucketId, template: template, composed: composed,
                        unhingedLevel: unhingedLevel, toneValue: toneValue)

                    let text = try await FoundationModelsProvider().generate(context)
                    // No caching — every generation is live.

                    // Validate the generated text
                    let validation = validator.validate(text, forBucket: bucketId, recentHistory: recentTexts)
                    switch validation {
                    case .valid(let validText):
                        // Track the register that produced this signoff
                        let register = composed.prompt.components(separatedBy: "Channel ").last?.components(separatedBy: " for this").first
                        let finalText = PostProcessor.appendFooter(validText, profile: snapshot, mode: postfixMode)
                        let latencyMs = Int(Date().timeIntervalSince(t0) * 1000)
                        let outcome = GenerationOutcome(
                            text: finalText, providerKind: .foundationModels,
                            latencyMs: latencyMs, bucketId: bucketId, tone: nil)
                        self.lastResult = outcome
                        self.lastStatus = nil
                        UsageTracker.shared.increment()
                        await persistence?.recordGeneration(
                            bucketId: outcome.bucketId, text: outcome.text,
                            providerRaw: outcome.providerKind.rawValue, latencyMs: outcome.latencyMs,
                            register: register)
                        SignoffSignpost.recordGenerateLatency(provider: .foundationModels, latencyMs: latencyMs)
                        GenerationDebugProbe.shared.recordEvent(
                            "live fmf ok \(bucketId) \(latencyMs)ms (attempt \(attempt))")
                        return .success(outcome)

                    case .invalid(let reason):
                        Self.log.info("[GenerationService] Validation failed (attempt \(attempt)): \(reason, privacy: .public)")
                        GenerationDebugProbe.shared.recordEvent("validation fail \(bucketId) attempt \(attempt): \(reason)")

                        // Last attempt? fall through to honest failure. Else
                        // continue with a corrective prompt + a different register.
                        if attempt == maxAttempts {
                            break
                        }
                        continue
                    }
                } catch {
                    if attempt < maxAttempts {
                        let delay = UInt64(500_000_000 * attempt)
                        try? await Task.sleep(nanoseconds: delay)
                    } else {
                        self.lastStatus = nil
                        GenerationDebugProbe.shared.recordEvent(
                            "live fmf fail \(bucketId): \(error.localizedDescription)")
                    }
                }
            } else {
                return .providerFailed(reason: "Foundation Models require macOS 26+")
            }
        }

        // All live attempts exhausted — honest failure. No hardcoded fallback:
        // a signoff is always generated or the app reports it couldn't.
        GenerationDebugProbe.shared.recordEvent("all \(maxAttempts) attempts exhausted \(bucketId)")
        return .providerFailed(reason: "Couldn't generate a passing signoff after \(maxAttempts) attempts. Try again in a moment.")
    }

    public func warmup() async {
        FoundationModelsAvailability.shared.refresh()
    }

    @available(macOS 26, *)
    public func prewarmFoundationModels() async {
#if canImport(FoundationModels)
        let status = FoundationModelsAvailability.probe()
        guard case .available = status else { return }

        // Create voice profile snapshot on main actor, then use it in nonisolated context
        let voiceSnapshot = await MainActor.run {
            PromptComposer.VoiceProfileSnapshot(from: VoiceProfile.shared)
        }

        let template = await PromptTemplate.load(bucket: BucketID.standard.rawValue) ?? .fallback
        let composed = PromptComposer.compose(
            template: template, profile: UserProfileSnapshot(profile: nil), recentTexts: [],
            voiceProfile: voiceSnapshot)
        await FoundationModelsSessionPool.shared.prewarm(
            bucketId: BucketID.standard.rawValue,
            instructions: composed.instructions, promptPrefix: composed.promptPrefix)
        for bid in [BucketID.professional, .unhinged] {
            let t = await PromptTemplate.load(bucket: bid.rawValue) ?? .fallback
            let c = PromptComposer.compose(
                template: t, profile: UserProfileSnapshot(profile: nil), recentTexts: [],
                voiceProfile: voiceSnapshot)
            await FoundationModelsSessionPool.shared.prewarm(
                bucketId: bid.rawValue, instructions: c.instructions, promptPrefix: c.promptPrefix)
        }
        await MainActor.run {
            FoundationModelsAvailability.shared.refresh()
            SignoffLogLogger(.generation).info("Foundation Models prewarmed")
        }
#endif
    }

    /// True when the on-device Apple Foundation Model is available and ready.
    private func foundationModelsIsReady() -> Bool {
        if #available(macOS 26, *) {
            if case .available = FoundationModelsAvailability.probe() { return true }
        }
        return false
    }

    /// Public check for Foundation Models readiness - useful for tests
    @MainActor
    public func isFoundationModelsReady() -> Bool {
        if #available(macOS 26, *) {
            if case .available = FoundationModelsAvailability.probe() { return true }
        }
        return false
    }
}