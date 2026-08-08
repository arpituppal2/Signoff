import Foundation
import os
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The single entry point for generation. **On-device only.**
///
/// Hybrid strategy:
/// 1. Live Foundation Models generation with bucket-specific prompts and rotating curated examples
/// 2. Local SignoffQualityValidator filters output (banned tokens, similarity, length, narration, format)
/// 3. Up to 2 retries with corrective instructions when validation fails
/// 4. Curated fallback from 130+ high-quality entries per bucket (mechanism-diverse, history-aware)
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
        let template = PromptTemplate.load(bucket: bucketId) ?? .fallback
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

        // Load corpus for curated fallback
        SignoffCorpusLoader.shared.load()

        // ── Hybrid: Live FMF → Validate → Retry (corrective) → Curated Fallback ──
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

        // On-device model not ready — curated fallback directly
        let status = FoundationModelsAvailability.probe()
        GenerationDebugProbe.shared.setModelActive(false)
        GenerationDebugProbe.shared.recordEvent("model not ready: \(status.titleForFailure)")
        self.lastStatus = .foundationModelsUnavailable(used: .foundationModels)

        // Try curated fallback when model unavailable
        if let curated = await selectCuratedFallback(bucketId: bucketId, recentTexts: recentTexts) {
            let finalText = PostProcessor.appendFooter(curated.text, profile: snapshot, mode: postfixMode)
            let latencyMs = Int(Date().timeIntervalSince(t0) * 1000)
            let outcome = GenerationOutcome(
                text: finalText, providerKind: .foundationModels,
                latencyMs: latencyMs, bucketId: bucketId, tone: nil)
            self.lastResult = outcome
            UsageTracker.shared.increment()
            await persistence?.recordGeneration(
                bucketId: outcome.bucketId, text: outcome.text,
                providerRaw: outcome.providerKind.rawValue, latencyMs: outcome.latencyMs)
            return .success(outcome)
        }

        return .providerFailed(reason: FoundationModelsAvailability.userFacingCause(for: status))
    }

    /// Hybrid generation pipeline: Live FMF → Validate → Retry (corrective) → Curated Fallback
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

        // Three attempts: live + 2 corrective retries
        for attempt in 1...3 {
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
                    // Compose prompt with rotating curated examples
                    // Fetch curated examples for few-shot prompting
                    SignoffCorpusLoader.shared.load()
                    let corpusEntries = SignoffCorpusLoader.shared.corpus.entries(for: bucketId)
                    let availableEntries = corpusEntries.filter { !existingMechanisms.contains($0.mechanism) }
                    let selectedEntries = availableEntries.shuffled().prefix(3)
                    let curatedExamples = selectedEntries.isEmpty
                        ? corpusEntries.shuffled().prefix(3).map { $0.text }
                        : selectedEntries.map { $0.text }

                    let composed = PromptComposer.compose(
                        template: template, profile: snapshot, recentTexts: recentTexts,
                        unhingedLevel: unhingedLevel, toneValue: toneValue, postfixMode: postfixMode,
                        customInstructions: customInstructions, phraseList: phraseList,
                        ageGroup: voice,
                        voiceProfile: voiceSnapshot,
                        nsfwEnabled: nsfwEnabled,
                        attempt: attempt,
                        usedMechanisms: existingMechanisms,
                        curatedExamples: curatedExamples)

                    let context = ProviderGenerateContext(
                        bucketId: bucketId, template: template, composed: composed,
                        unhingedLevel: unhingedLevel, toneValue: toneValue,
                        guardWords: template.guardWords)

                    let text = try await FoundationModelsProvider().generate(context)
                    // No caching — every generation is live.

                    // Validate the generated text
                    let validation = validator.validate(text, forBucket: bucketId, recentHistory: recentTexts)
                    switch validation {
                    case .valid(let validText):
                        // Track mechanism if we can infer it (for next rotation)
                        // For now just track that we used FMF successfully
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
                            providerRaw: outcome.providerKind.rawValue, latencyMs: outcome.latencyMs)
                        SignoffSignpost.recordGenerateLatency(provider: .foundationModels, latencyMs: latencyMs)
                        GenerationDebugProbe.shared.recordEvent(
                            "live fmf ok \(bucketId) \(latencyMs)ms (attempt \(attempt))")
                        return .success(outcome)

                    case .invalid(let reason):
                        Self.log.info("[GenerationService] Validation failed (attempt \(attempt)): \(reason, privacy: .public)")
                        GenerationDebugProbe.shared.recordEvent("validation fail \(bucketId) attempt \(attempt): \(reason)")

                        // If this was the last attempt, fall through to curated
                        if attempt == 3 {
                            break
                        }
                        // Otherwise continue loop with corrective prompt on next iteration
                        continue
                    }
                } catch {
                    if attempt < 3 {
                        let delay = UInt64(500_000_000 * attempt)
                        try? await Task.sleep(nanoseconds: delay)
                    } else {
                        self.lastStatus = nil
                        GenerationDebugProbe.shared.recordEvent(
                            "live fmf fail \(bucketId): \(error.localizedDescription)")
                        // Continue to curated fallback
                    }
                }
            } else {
                return .providerFailed(reason: "Foundation Models require macOS 26+")
            }
        }

        // All live attempts exhausted — curated fallback
        if let curated = await selectCuratedFallback(bucketId: bucketId, recentTexts: recentTexts, usedMechanisms: existingMechanisms) {
            // Track the mechanism we used
            var mechanisms = usedMechanisms[bucketId] ?? []
            mechanisms.append(curated.mechanism)
            // Keep last 10 mechanisms for diversity
            if mechanisms.count > 10 { mechanisms.removeFirst(mechanisms.count - 10) }
            usedMechanisms[bucketId] = mechanisms

            let finalText = PostProcessor.appendFooter(curated.text, profile: snapshot, mode: postfixMode)
            let latencyMs = Int(Date().timeIntervalSince(t0) * 1000)
            let outcome = GenerationOutcome(
                text: finalText, providerKind: .foundationModels,
                latencyMs: latencyMs, bucketId: bucketId, tone: nil)
            self.lastResult = outcome
            UsageTracker.shared.increment()
            await persistence?.recordGeneration(
                bucketId: outcome.bucketId, text: outcome.text,
                providerRaw: outcome.providerKind.rawValue, latencyMs: outcome.latencyMs)
            GenerationDebugProbe.shared.recordEvent("curated fallback \(bucketId) mechanism=\(curated.mechanism)")
            return .success(outcome)
        }

        return .providerFailed(reason: "Generation failed after multiple attempts and no curated fallback available")
    }

    /// Select a curated fallback entry, avoiding recent history and prioritizing mechanism diversity
    private func selectCuratedFallback(bucketId: String, recentTexts: [String], usedMechanisms: [String] = []) async -> CuratedSignoff? {
        return SignoffQualityValidator.shared.selectCuratedFallback(
            forBucket: bucketId,
            recentHistory: recentTexts,
            usedMechanisms: usedMechanisms
        )
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

        let template = PromptTemplate.load(bucket: BucketID.standard.rawValue) ?? .fallback
        let composed = PromptComposer.compose(
            template: template, profile: UserProfileSnapshot(profile: nil), recentTexts: [],
            voiceProfile: voiceSnapshot)
        await FoundationModelsSessionPool.shared.prewarm(
            bucketId: BucketID.standard.rawValue,
            instructions: composed.instructions, promptPrefix: composed.promptPrefix)
        for bid in [BucketID.professional, .unhinged] {
            let t = PromptTemplate.load(bucket: bid.rawValue) ?? .fallback
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