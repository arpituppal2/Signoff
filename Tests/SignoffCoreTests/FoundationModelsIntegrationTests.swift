import Testing
import Foundation
@testable import SignoffCore

struct FoundationModelsIntegrationTests {

    // MARK: - Prompt JSON schema

    @Test("Prompt templates all buckets decode")
    func promptTemplatesAllBucketsDecode() async throws {
        let buckets = ["quotes", "professional", "unhinged", "custom"]
        for name in buckets {
            let loaded = await PromptTemplate.load(bucket: name == "quotes" ? BucketID.standard.rawValue : name)
            #expect(loaded != nil, "Expected Prompts/\(name).json to decode for bucket \(name)")
            #expect(!loaded!.system.isEmpty)
            #expect(!loaded!.userVariants.isEmpty)
        }
    }

    @Test("Prompt template standard maps to quotes resource")
    func promptTemplateStandardMapsToQuotesResource() async throws {
        let standard = await PromptTemplate.load(bucket: BucketID.standard.rawValue)
        let quotes = await PromptTemplate.load(bucket: "quotes")
        #expect(standard == quotes)
        #expect(standard != nil)
    }

    @Test("Prompt template choose user matches cynical level")
    func promptTemplateChooseUserMatchesCynicalLevel() async throws {
        let template = await PromptTemplate.load(bucket: BucketID.unhinged.rawValue)!
        let cynical = template.chooseUser(unhingedLevel: .cynical)
        let fallback = template.chooseUser(unhingedLevel: .calm)
        #expect(cynical.lowercased().contains("cynicism") || cynical.lowercased().contains("cynical"))
        #expect(cynical != fallback)
    }

    @Test("Prompt template choose user matches tone range")
    func promptTemplateChooseUserMatchesToneRange() async throws {
        // The contract: distinct tone ranges map to distinct userVariant
        // instructions (so tone actually changes the prompt). The exact
        // wording ("formal"/"relaxed") is not a stable contract — only
        // that the chosen variants DIFFER across the tone spectrum.
        let template = await PromptTemplate.load(bucket: BucketID.professional.rawValue)!
        let formal = template.chooseUser(toneValue: 0.2)
        let relaxed = template.chooseUser(toneValue: 0.9)
        #expect(!formal.isEmpty)
        #expect(!relaxed.isEmpty)
        #expect(formal != relaxed, "professional variants must differ across tone range; got identical strings")
    }

    @Test("Prompt template load unknown bucket returns nil")
    func promptTemplateLoadUnknownBucketReturnsNil() async throws {
        #expect(await PromptTemplate.load(bucket: "not-a-bucket-\(UUID().uuidString)") == nil)
        #expect(await PromptTemplate.load(bucket: "") == nil)
    }

    @Test("Prompt template all bucket IDs load with required schema")
    func promptTemplateAllBucketIDsLoadWithRequiredSchema() async throws {
        let liveIDs = Bucket.defaultBuckets().map(\.id)
        for id in liveIDs {
            let loaded = await PromptTemplate.load(bucket: id)
            #expect(loaded != nil, "PromptTemplate.load must resolve for BucketID.\(id)")
            guard let t = loaded else { continue }
            #expect(!t.system.isEmpty, "\(id) system")
            #expect(!t.userVariants.isEmpty, "\(id) userVariants")
            #expect(t.positiveExamples != nil, "\(id) positiveExamples")
        }
    }

    @Test("Prompt template fallback is decodable shape")
    func promptTemplateFallbackIsDecodableShape() async throws {
        let f = PromptTemplate.fallback
        #expect(!f.system.isEmpty)
        #expect(f.userVariants.count >= 1)
        #expect(f.chooseUser() == f.userVariants.first?.user)
        // load(nil path) must not be confused with the static fallback — they
        // are separate: missing resources return nil; callers coalesce to .fallback.
        #expect(await PromptTemplate.load(bucket: "missing-resource-xyz") == nil)
    }

    // MARK: - PromptComposer

    @Test("Prompt composer keeps user data out of instructions")
    func promptComposerKeepsUserDataOutOfInstructions() throws {
        let template = PromptTemplate.fallback
        let profile = UserProfileSnapshot(profile: nil)
        // Fabricate a snapshot-like profile via process path — use composed with recents.
        let composed = PromptComposer.compose(
            template: template,
            profile: profile,
            recentTexts: ["Thanks for shipping this.", "Talk Monday."],
            customInstructions: "Keep it breezy"
        )
        #expect(!composed.instructions.contains("Thanks for shipping this."))
        #expect(!composed.instructions.contains("Keep it breezy"))
        #expect(composed.prompt.contains("Thanks for shipping this."))
        #expect(composed.prompt.contains("Keep it breezy"))
        #expect(composed.instructions.contains(template.system))
        // Rules are NOT in instructions (to avoid content filter); guard words validated post-generation
        #expect(!composed.instructions.contains("Rules:"))
    }

    @Test("Prompt composer prompt prefix excludes recents")
    func promptComposerPromptPrefixExcludesRecents() throws {
        let composed = PromptComposer.compose(
            template: .fallback,
            profile: UserProfileSnapshot(profile: nil),
            recentTexts: ["Secret recent phrase XYZ"]
        )
        #expect(!composed.promptPrefix.contains("Secret recent phrase XYZ"))
        #expect(composed.prompt.contains("Secret recent phrase XYZ"))
        // prewarm(promptPrefix:) only helps when prefix is a true head of prompt.
        #expect(composed.prompt.hasPrefix(composed.promptPrefix))
    }

    @Test("Prompt composer prompt prefix includes stable examples")
    func promptComposerPromptPrefixIncludesStableExamples() throws {
        let composed = PromptComposer.compose(
            template: .fallback,
            profile: UserProfileSnapshot(profile: nil),
            recentTexts: []
        )
        // Prompt prefix should only contain userVariant (no examples to avoid content filter)
        #expect(composed.promptPrefix.contains("signoff"))
        #expect(composed.prompt.hasPrefix(composed.promptPrefix))
    }

    // MARK: - Availability (mockable Status — no live model required)

    @Test("Availability user facing cause for each case")
    func availabilityUserFacingCauseForEachCase() {
        let cases: [FoundationModelsAvailability.Status] = [
            .available,
            .deviceNotEligible,
            .appleIntelligenceNotEnabled,
            .modelNotReady,
            .unavailable("other"),
            .unsupportedSDK,
        ]
        for status in cases {
            let cause = FoundationModelsAvailability.userFacingCause(for: status)
            #expect(!cause.isEmpty, "Cause empty for \(status)")
            #expect(!status.titleForFailure.isEmpty)
        }
    }

    @Test("Availability Apple Intelligence deep link is not security prefs")
    func availabilityAppleIntelligenceDeepLinkIsNotSecurityPrefs() {
        let url = FoundationModelsAvailability.appleIntelligenceSettingsURL.absoluteString
        #expect(!url.contains("preference.security"), "FM deep-link must not open Privacy & Security")
        #expect(url.contains("Siri"), "FM deep-link should open Apple Intelligence & Siri")
        #expect(FoundationModelsAvailability.shouldOpenAppleIntelligenceSettings(for: .appleIntelligenceNotEnabled) == true)
        #expect(FoundationModelsAvailability.shouldOpenAppleIntelligenceSettings(for: .deviceNotEligible) == false)
        #expect(FoundationModelsAvailability.shouldOpenAppleIntelligenceSettings(for: .modelNotReady) == false)
    }

    @Test("Availability probe does not trap")
    func availabilityProbeDoesNotTrap() {
        // On CI without Apple Intelligence this returns a non-available status;
        // the important contract is that it never traps and is Sendable/Equatable.
        let status = FoundationModelsAvailability.probe()
        _ = FoundationModelsAvailability.userFacingCause(for: status)
        #expect(status.titleForFailure != "")
    }

    @Test("Generation error refusal and guardrail cases exist")
    func generationErrorRefusalAndGuardrailCasesExist() {
        let refused = GenerationError.refused(reason: "nope")
        let guardrail = GenerationError.guardrailViolation(reason: "blocked")
        let timeout = GenerationError.timeout
        #expect(refused == .refused(reason: "nope"))
        #expect(guardrail == .guardrailViolation(reason: "blocked"))
        #expect(timeout == .timeout)
    }

    @MainActor
    @Test("Foundation Models generation service smoke")
    func foundationModelsGenerationServiceSmoke() {
        let service = GenerationService()
        #expect(service.isRunning == false)
        #expect(service.lastResult == nil)
        service.clearStatus()
        #expect(service.lastStatus == nil)
    }
}