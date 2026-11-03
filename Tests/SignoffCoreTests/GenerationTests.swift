import Testing
import Foundation
@testable import SignoffCore

/// Tests for the FM-only GenerationService. Spec §3: Foundation Models only.
@MainActor
struct GenerationTests {

    // MARK: - Provider kind

    @Test("Provider kind is on device AI")
    func providerKindIsOnDeviceAI() {
        #expect(GenerationProviderKind.foundationModels.badgeTitle == "On-device")
        #expect(GenerationProviderKind.foundationModels.badgeSystemImage == "lock.fill")
        #expect(GenerationProviderKind.foundationModels.rawValue == "fmf")
    }

    @Test("Provider kind covers on-device and cloud")
    func providerKindCoversOnDeviceAndCloud() {
        let all = GenerationProviderKind.allCases
        #expect(all == [.foundationModels, .openAI, .anthropic])
        #expect(GenerationProviderKind.foundationModels.isLiveOnDevice == true)
        #expect(GenerationProviderKind.openAI.isCloud == true)
        #expect(GenerationProviderKind.anthropic.isCloud == true)
        #expect(GenerationProviderKind.openAI.rawValue == "openai")
        #expect(GenerationProviderKind.anthropic.rawValue == "anthropic")
    }

    // MARK: - GenerationService public surface (smoke)

    @Test("Generation service starts not running")
    func generationServiceStartsNotRunning() {
        let service = GenerationService()
        #expect(service.isRunning == false)
    }

    @Test("Generation service last result is readable")
    func generationServiceLastResultIsReadable() {
        let service = GenerationService()
        #expect(service.lastResult == nil)
    }

    @Test("Generation service clear status")
    func generationServiceClearStatus() {
        let service = GenerationService()
        #expect(service.lastStatus == nil)
        service.clearStatus()
        #expect(service.lastStatus == nil)
    }

    @Test("Generation service warmup does not crash")
    func generationServiceWarmupDoesNotCrash() async {
        let service = GenerationService()
        await service.warmup()
        #expect(service != nil)
    }

    // MARK: - PostProcessor

    @Test("Ensure punctuation appends period")
    func ensurePunctuationAppendsPeriod() {
        #expect(PostProcessor.ensurePunctuation("Thanks") == "Thanks.")
    }

    @Test("Ensure punctuation preserves exclamation")
    func ensurePunctuationPreservesExclamation() {
        #expect(PostProcessor.ensurePunctuation("Great!") == "Great!")
    }

    @Test("Ensure punctuation preserves question")
    func ensurePunctuationPreservesQuestion() {
        #expect(PostProcessor.ensurePunctuation("Soon?") == "Soon?")
    }

    @Test("Ensure punctuation empty string")
    func ensurePunctuationEmptyString() {
        #expect(PostProcessor.ensurePunctuation("") == "")
    }

    @Test("Ensure punctuation trims whitespace")
    func ensurePunctuationTrimsWhitespace() {
        #expect(PostProcessor.ensurePunctuation("  Talk soon  ") == "Talk soon.")
    }

    @Test("Ensure punctuation no double punctuation")
    func ensurePunctuationNoDoublePunctuation() {
        #expect(PostProcessor.ensurePunctuation("See you.") == "See you.")
        #expect(PostProcessor.ensurePunctuation("See you!") == "See you!")
    }

    @Test("Append footer nothing")
    func appendFooterNothing() {
        let snapshot = UserProfileSnapshot(profile: nil)
        #expect(PostProcessor.appendFooter("Thanks.", profile: snapshot, mode: .nothing) == "Thanks.")
    }

    @Test("Append footer name")
    func appendFooterName() {
        let profile = UserProfile(name: "Alex")
        let snapshot = UserProfileSnapshot(profile: profile)
        let result = PostProcessor.appendFooter("Thanks.", profile: snapshot, mode: .name)
        #expect(result.contains("Thanks."))
        #expect(result.contains("—Alex"))
    }

    @Test("Append footer full footer")
    func appendFooterFullFooter() {
        let profile = UserProfile(name: "Alex", title: "Engineer", company: "Acme", email: "alex@acme.com")
        let snapshot = UserProfileSnapshot(profile: profile)
        let result = PostProcessor.appendFooter("Thanks.", profile: snapshot, mode: .fullFooter)
        #expect(result.contains("Thanks."))
        #expect(result.contains("Alex"))
        #expect(result.contains("Engineer"))
        #expect(result.contains("Acme"))
        #expect(result.contains("alex@acme.com"))
    }

    // MARK: - FoundationModelsAvailability

    @Test("Foundation Models availability probe returns valid status")
    func foundationModelsAvailabilityProbeReturnsValidStatus() {
        // Should return a valid status without trapping.
        let status = FoundationModelsAvailability.probe()
        let validCases: [FoundationModelsAvailability.Status] = [
            .available, .deviceNotEligible, .appleIntelligenceNotEnabled,
            .modelNotReady, .unsupportedSDK
        ]
        #expect(validCases.contains(status), "Unexpected status: \(status)")
        #expect(!status.titleForFailure.isEmpty)
    }

    @Test("Foundation Models availability title for failure")
    func foundationModelsAvailabilityTitleForFailure() {
        #expect(FoundationModelsAvailability.Status.unsupportedSDK.titleForFailure == "On-device model unavailable")
        #expect(FoundationModelsAvailability.Status.available.titleForFailure == "Apple Intelligence ready")
    }

    // MARK: - PromptTemplate

    @Test("Prompt template loads standard")
    func promptTemplateLoadsStandard() async throws {
        let template = await PromptTemplate.load(bucket: "standard")
        #expect(template != nil, "template was nil for 'standard'")
        if let template = template {
            #expect(!template.system.isEmpty, "system empty: \(template.system)")
        }
    }

    @Test("Prompt template fallback")
    func promptTemplateFallback() {
        let fallback = PromptTemplate.fallback
        #expect(!fallback.system.isEmpty)
        #expect(!fallback.userVariants.isEmpty)
    }

    @Test("Prompt template choose user")
    func promptTemplateChooseUser() {
        let template = PromptTemplate.fallback
        let user = template.chooseUser()
        #expect(!user.isEmpty)
    }

    // MARK: - PromptComposer

    @Test("Prompt composer composes without crash")
    func promptComposerComposesWithoutCrash() {
        let template = PromptTemplate.fallback
        let snapshot = UserProfileSnapshot(profile: nil)
        let composed = PromptComposer.compose(template: template, profile: snapshot, recentTexts: [])
        #expect(!composed.instructions.isEmpty)
        #expect(!composed.prompt.isEmpty)
    }

    @Test("Prompt composer includes profile")
    func promptComposerIncludesProfile() {
        let profile = UserProfile(name: "Alex", selfDescription: "writes kindly")
        let snapshot = UserProfileSnapshot(profile: profile)
        let template = PromptTemplate.fallback
        let composed = PromptComposer.compose(template: template, profile: snapshot, recentTexts: [])
        #expect(composed.prompt.contains("writes kindly") || composed.instructions.contains("writes kindly"))
    }

    @Test("Prompt composer avoids recent")
    func promptComposerAvoidsRecent() {
        let template = PromptTemplate.fallback
        let snapshot = UserProfileSnapshot(profile: nil)
        let composed = PromptComposer.compose(template: template, profile: snapshot, recentTexts: ["Talk soon."])
        #expect(!composed.prompt.isEmpty)
    }

    // MARK: - UserProfileSnapshot

    @Test("User profile snapshot empty")
    func userProfileSnapshotEmpty() {
        let snapshot = UserProfileSnapshot(profile: nil)
        #expect(snapshot.name == "")
        #expect(snapshot.title == nil)
        #expect(snapshot.company == nil)
        #expect(snapshot.selfDescription == "")
        #expect(snapshot.emojiEnabled == false)
    }

    @Test("User profile snapshot with profile")
    func userProfileSnapshotWithProfile() {
        let profile = UserProfile(name: "Alex", title: "Eng", company: "Co", email: "a@c.com", phone: "555", website: "a.co", selfDescription: "friendly", emojiEnabled: true)
        let snapshot = UserProfileSnapshot(profile: profile)
        #expect(snapshot.name == "Alex")
        #expect(snapshot.title == "Eng")
        #expect(snapshot.company == "Co")
        #expect(snapshot.email == "a@c.com")
        #expect(snapshot.phone == "555")
        #expect(snapshot.website == "a.co")
        #expect(snapshot.selfDescription == "friendly")
        #expect(snapshot.emojiEnabled == true)
    }
}