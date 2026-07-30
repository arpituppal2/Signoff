import Foundation
import os
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The single entry point for generation. **On-device only.**
///
/// Every phrase is drafted by Apple Foundation Models running locally on this
/// Mac. Free tier reads from a per-bucket cache that
/// `GenerationRefillCoordinator` keeps warm in the background; a cache pop is a
/// cached *on-device-generated* phrase served instantly (<1ms), and the
/// background refill writes the next one. A cache miss falls through to a live
/// ~1s on-device call that also fills the cache.
///
/// There is **no offline phrasebook** and no static fallback. If the on-device
/// model isn't ready, generation fails honestly (`providerFailed`) instead of
/// serving something pre-written. That is the whole point — the model actually
/// runs, so its ANE/GPU cost is real and the output varies every time.
@MainActor
public final class GenerationService: ObservableObject {
    public static let shared = GenerationService()

    @Published public private(set) var lastResult: GenerationOutcome?
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var lastStatus: GenerationStatusNotice?
    /// Published so the popover can show tier/usage status.
    @Published public private(set) var usageLimitReached: Bool = false

    private var inflightRequest: Bool = false

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
                         ageGroup: AgeGroup? = nil) async -> Outcome {
        let signpostID = SignoffSignpost.generateProvider.makeSignpostID()
        let state = SignoffSignpost.generateProvider.beginInterval(
            "generate", id: signpostID, "bucket: \(bucketId, privacy: .public)")
        defer { SignoffSignpost.generateProvider.endInterval("generate", state) }

        if inflightRequest {
            return .providerFailed(reason: "Generation already in progress")
        }

        // Usage limit — durable & redownload-proof (see UsageTracker).
        guard UsageTracker.shared.canGenerate else {
            usageLimitReached = true
            return .usageLimitReached
        }
        usageLimitReached = false

        inflightRequest = true
        defer { inflightRequest = false }
        isRunning = true
        defer { isRunning = false }

        let t0 = Date()
        return await runGeneration(
            bucketId: bucketId, profile: profile, recentTexts: recentTexts,
            unhingedLevel: unhingedLevel, toneValue: toneValue,
            postfixMode: postfixMode, customInstructions: customInstructions,
            phraseList: phraseList, ageGroup: ageGroup, t0: t0)
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
                               t0: Date) async -> Outcome {
        let snapshot = UserProfileSnapshot(profile: profile)
        let template = PromptTemplate.load(bucket: bucketId) ?? .fallback
        let voice = ageGroup ?? .genZ

        // Get the voice profile for discriminative prompting
        let voiceProfile = VoiceProfile.shared

        // ── Paid tier: context-aware FMF (signoff depends on the message) ──
        if UsageTracker.shared.isOnPaidTier {
            var contextInstructions = ""
            if let harvested = await ContextHarvester.shared.harvest() {
                contextInstructions = "The user is replying to this message: \"\(harvested.messageText)\". "
                SignoffLogLogger(.generation)
                    .info("Harvested context from \(harvested.sourceApp, privacy: .public)")
            }
            return await executeFMFGeneration(
                bucketId: bucketId, snapshot: snapshot, template: template,
                recentTexts: recentTexts, unhingedLevel: unhingedLevel,
                toneValue: toneValue, postfixMode: postfixMode,
                customInstructions: customInstructions, phraseList: phraseList,
                voice: voice, contextInstructions: contextInstructions, t0: t0,
                voiceProfile: voiceProfile)
        }

        // ── Free tier: cache-first for instant generation (< 1ms) ──
        // The cache is filled *only* by Apple Foundation Models, so a hit is a
        // real on-device generation served instantly. No static seed exists.
        if let hit = BucketCache.shared.pop(bucketId: bucketId) {
            let finalText = PostProcessor.appendFooter(hit.phrase, profile: snapshot, mode: postfixMode)
            let latencyMs = Int(Date().timeIntervalSince(t0) * 1000)
            let outcome = GenerationOutcome(
                text: finalText, providerKind: hit.source,
                latencyMs: latencyMs, bucketId: bucketId, tone: nil)
            self.lastResult = outcome
            self.lastStatus = nil
            UsageTracker.shared.incrementCount()
            await persistence?.recordGeneration(
                bucketId: outcome.bucketId, text: outcome.text,
                providerRaw: outcome.providerKind.rawValue, latencyMs: outcome.latencyMs)
            SignoffSignpost.recordGenerateLatency(provider: hit.source, latencyMs: latencyMs)

            // Write the next one in the background so the next pop is instant.
            scheduleBackgroundRefill(
                bucketId: bucketId, snapshot: snapshot, template: template,
                recentTexts: recentTexts + [hit.phrase], unhingedLevel: unhingedLevel,
                toneValue: toneValue, postfixMode: postfixMode,
                customInstructions: customInstructions, phraseList: phraseList,
                voice: voice, voiceProfile: voiceProfile)
            return .success(outcome)
        }

        // ── Cache miss: the only remaining path is a live on-device call.
        // No fallback exists. If the model isn't ready, fail honestly.
        if foundationModelsIsReady() {
            return await executeFMFGeneration(
                bucketId: bucketId, snapshot: snapshot, template: template,
                recentTexts: recentTexts, unhingedLevel: unhingedLevel,
                toneValue: toneValue, postfixMode: postfixMode,
                customInstructions: customInstructions, phraseList: phraseList,
                voice: voice, contextInstructions: nil, t0: t0,
                voiceProfile: voiceProfile)
        }

        // On-device model not ready — tell the truth. Never serve a canned line.
        let status = FoundationModelsAvailability.probe()
        self.lastStatus = .foundationModelsUnavailable(used: .foundationModels)
        return .providerFailed(reason: FoundationModelsAvailability.userFacingCause(for: status))
    }

    /// Kick a background Foundation Models refill for a bucket so the cache
    /// stays warm with on-device-generated phrases.
    private nonisolated func scheduleBackgroundRefill(bucketId: String,
                                                      snapshot: UserProfileSnapshot,
                                                      template: PromptTemplate,
                                                      recentTexts: [String],
                                                      unhingedLevel: UnhingedLevel?,
                                                      toneValue: Double?,
                                                      postfixMode: BucketPostfixMode,
                                                      customInstructions: String?,
                                                      phraseList: String?,
                                                      voice: AgeGroup,
                                                      voiceProfile: VoiceProfile) {
        // Capture voice profile data in a Sendable snapshot on the main actor, then use it in the detached task
        let voiceSnapshot = PromptComposer.VoiceProfileSnapshot(from: voiceProfile)
        Task.detached(priority: .utility) {
            await GenerationRefillCoordinator.shared.refillIfNeeded(
                bucketId: bucketId,
                template: template,
                profile: snapshot,
                recentTexts: recentTexts,
                config: .init(
                    unhingedLevel: unhingedLevel,
                    toneValue: toneValue,
                    customInstructions: customInstructions,
                    phraseList: phraseList,
                    postfixMode: postfixMode
                ),
                ageGroup: voice,
                voiceProfile: voiceSnapshot,
                fillCount: BucketCache.fillCount)
        }
    }

    /// Shared FMF generation pipeline — used by both free (cache miss) and paid (context-aware).
    private func executeFMFGeneration(bucketId: String,
                                      snapshot: UserProfileSnapshot,
                                      template: PromptTemplate,
                                      recentTexts: [String],
                                      unhingedLevel: UnhingedLevel?,
                                      toneValue: Double?,
                                      postfixMode: BucketPostfixMode,
                                      customInstructions: String?,
                                      phraseList: String?,
                                      voice: AgeGroup,
                                      contextInstructions: String?,
                                      t0: Date,
                                      voiceProfile: VoiceProfile) async -> Outcome {
        // Create Sendable snapshot of voice profile
        let voiceSnapshot = PromptComposer.VoiceProfileSnapshot(from: voiceProfile)
        let composed = PromptComposer.compose(
            template: template, profile: snapshot, recentTexts: recentTexts,
            unhingedLevel: unhingedLevel, toneValue: toneValue, postfixMode: postfixMode,
            customInstructions: customInstructions, phraseList: phraseList,
            contextInstructions: contextInstructions,
            ageGroup: voice,
            voiceProfile: voiceSnapshot)

        let context = ProviderGenerateContext(
            bucketId: bucketId, template: template, composed: composed,
            unhingedLevel: unhingedLevel, toneValue: toneValue)

        // FMF generation with retry — up to 3 attempts with backoff.
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
                    let text = try await FoundationModelsProvider().generate(context)
                    // Cache raw text (no footer) so cache hits never double-footer.
                    BucketCache.shared.fill(bucketId: bucketId, phrases: [text])

                    let finalText = PostProcessor.appendFooter(text, profile: snapshot, mode: postfixMode)
                    let latencyMs = Int(Date().timeIntervalSince(t0) * 1000)
                    let outcome = GenerationOutcome(
                        text: finalText, providerKind: .foundationModels,
                        latencyMs: latencyMs, bucketId: bucketId, tone: nil)
                    self.lastResult = outcome
                    self.lastStatus = nil
                    UsageTracker.shared.incrementCount()
                    await persistence?.recordGeneration(
                        bucketId: outcome.bucketId, text: outcome.text,
                        providerRaw: outcome.providerKind.rawValue, latencyMs: outcome.latencyMs)
                    SignoffSignpost.recordGenerateLatency(provider: .foundationModels, latencyMs: latencyMs)
                    return .success(outcome)
                } catch {
                    if attempt < 3 {
                        let delay = UInt64(500_000_000 * attempt)
                        try? await Task.sleep(nanoseconds: delay)
                    } else {
                        self.lastStatus = nil
                        return .providerFailed(reason: error.localizedDescription)
                    }
                }
            } else {
                return .providerFailed(reason: "Foundation Models require macOS 26+")
            }
        }
        return .providerFailed(reason: "Generation failed after multiple attempts")
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
        for bid in [BucketID.professional, .unhinged, .custom, .list, .footer] {
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
}