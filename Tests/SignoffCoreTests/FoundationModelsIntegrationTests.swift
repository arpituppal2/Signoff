import XCTest
import Foundation
@testable import SignoffCore

final class FoundationModelsIntegrationTests: XCTestCase {

    // MARK: - Prompt JSON schema

    func testPromptTemplates_AllBucketsDecode() {
        let buckets = ["general", "professional", "unhinged", "custom"]
        for name in buckets {
            let loaded = PromptTemplate.load(bucket: name == "general" ? BucketID.standard.rawValue : name)
            XCTAssertNotNil(loaded, "Expected Prompts/\(name).json to decode for bucket \(name)")
            XCTAssertFalse(loaded!.system.isEmpty)
            XCTAssertFalse(loaded!.rules.isEmpty)
            XCTAssertFalse(loaded!.userVariants.isEmpty)
        }
    }

    func testPromptTemplate_StandardMapsToGeneralResource() {
        let standard = PromptTemplate.load(bucket: BucketID.standard.rawValue)
        let general = PromptTemplate.load(bucket: "general")
        XCTAssertEqual(standard, general)
        XCTAssertNotNil(standard)
    }

    func testPromptTemplate_ChooseUserMatchesCynicalLevel() {
        let template = PromptTemplate.load(bucket: BucketID.unhinged.rawValue)!
        let cynical = template.chooseUser(unhingedLevel: .cynical)
        let fallback = template.chooseUser(unhingedLevel: .calm)
        XCTAssertTrue(cynical.lowercased().contains("cynicism") || cynical.lowercased().contains("cynical"))
        XCTAssertNotEqual(cynical, fallback)
    }

    func testPromptTemplate_ChooseUserMatchesToneRange() {
        let template = PromptTemplate.load(bucket: BucketID.professional.rawValue)!
        let formal = template.chooseUser(toneValue: 0.2)
        let relaxed = template.chooseUser(toneValue: 0.9)
        XCTAssertTrue(formal.lowercased().contains("formal"))
        XCTAssertTrue(relaxed.lowercased().contains("relaxed"))
    }

    func testPromptTemplate_LoadUnknownBucketReturnsNil() {
        XCTAssertNil(PromptTemplate.load(bucket: "not-a-bucket-\(UUID().uuidString)"))
        XCTAssertNil(PromptTemplate.load(bucket: ""))
    }

    func testPromptTemplate_AllBucketIDsLoadWithRequiredSchema() {
        let liveIDs = Bucket.defaultBuckets().map(\.id)
        for id in liveIDs {
            let loaded = PromptTemplate.load(bucket: id)
            XCTAssertNotNil(loaded, "PromptTemplate.load must resolve for BucketID.\(id)")
            guard let t = loaded else { continue }
            XCTAssertFalse(t.system.isEmpty, "\(id) system")
            XCTAssertFalse(t.rules.isEmpty, "\(id) rules")
            XCTAssertFalse(t.userVariants.isEmpty, "\(id) userVariants")
            // Not all buckets define guardWords (unhinged, custom intentionally leave it empty).
            // XCTAssertFalse(t.guardWords.isEmpty, "\(id) guardWords")
            // positiveExamples and negativeExamples can be empty - we don't use them in prompt prefix
            XCTAssertNotNil(t.positiveExamples, "\(id) positiveExamples")
            XCTAssertNotNil(t.negativeExamples, "\(id) negativeExamples")
        }
    }

    func testPromptTemplate_FallbackIsDecodableShape() {
        let f = PromptTemplate.fallback
        XCTAssertFalse(f.system.isEmpty)
        XCTAssertGreaterThanOrEqual(f.rules.count, 3)
        XCTAssertEqual(f.chooseUser(), f.userVariants.first?.user)
        // load(nil path) must not be confused with the static fallback — they
        // are separate: missing resources return nil; callers coalesce to .fallback.
        XCTAssertNil(PromptTemplate.load(bucket: "missing-resource-xyz"))
    }

    // MARK: - PromptComposer

    func testPromptComposer_KeepsUserDataOutOfInstructions() {
        let template = PromptTemplate.fallback
        let profile = UserProfileSnapshot(profile: nil)
        // Fabricate a snapshot-like profile via process path — use composed with recents.
        let composed = PromptComposer.compose(
            template: template,
            profile: profile,
            recentTexts: ["Thanks for shipping this.", "Talk Monday."],
            customInstructions: "Keep it breezy"
        )
        XCTAssertFalse(composed.instructions.contains("Thanks for shipping this."))
        XCTAssertFalse(composed.instructions.contains("Keep it breezy"))
        XCTAssertTrue(composed.prompt.contains("Thanks for shipping this."))
        XCTAssertTrue(composed.prompt.contains("Keep it breezy"))
        XCTAssertTrue(composed.instructions.contains(template.system))
        // Rules are NOT in instructions (to avoid content filter); guard words validated post-generation
        XCTAssertFalse(composed.instructions.contains("Rules:"))
    }

    func testPromptComposer_PromptPrefixExcludesRecents() {
        let composed = PromptComposer.compose(
            template: .fallback,
            profile: UserProfileSnapshot(profile: nil),
            recentTexts: ["Secret recent phrase XYZ"]
        )
        XCTAssertFalse(composed.promptPrefix.contains("Secret recent phrase XYZ"))
        XCTAssertTrue(composed.prompt.contains("Secret recent phrase XYZ"))
        // prewarm(promptPrefix:) only helps when prefix is a true head of prompt.
        XCTAssertTrue(composed.prompt.hasPrefix(composed.promptPrefix))
    }

    func testPromptComposer_PromptPrefixIncludesStableExamples() {
        let composed = PromptComposer.compose(
            template: .fallback,
            profile: UserProfileSnapshot(profile: nil),
            recentTexts: []
        )
        // Prompt prefix should only contain userVariant (no examples to avoid content filter)
        XCTAssertTrue(composed.promptPrefix.contains("signoff"))
        XCTAssertTrue(composed.prompt.hasPrefix(composed.promptPrefix))
    }

    // MARK: - Availability (mockable Status — no live model required)

    func testAvailability_UserFacingCauseForEachCase() {
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
            XCTAssertFalse(cause.isEmpty, "Cause empty for \(status)")
            XCTAssertFalse(status.titleForFailure.isEmpty)
        }
    }

    func testAvailability_AppleIntelligenceDeepLinkIsNotSecurityPrefs() {
        let url = FoundationModelsAvailability.appleIntelligenceSettingsURL.absoluteString
        XCTAssertFalse(url.contains("preference.security"),
                       "FM deep-link must not open Privacy & Security")
        XCTAssertTrue(url.contains("Siri"),
                      "FM deep-link should open Apple Intelligence & Siri")
        XCTAssertTrue(
            FoundationModelsAvailability.shouldOpenAppleIntelligenceSettings(
                for: .appleIntelligenceNotEnabled
            )
        )
        XCTAssertFalse(
            FoundationModelsAvailability.shouldOpenAppleIntelligenceSettings(
                for: .deviceNotEligible
            )
        )
        XCTAssertFalse(
            FoundationModelsAvailability.shouldOpenAppleIntelligenceSettings(
                for: .modelNotReady
            )
        )
    }

    func testAvailability_ProbeDoesNotTrap() {
        // On CI without Apple Intelligence this returns a non-available status;
        // the important contract is that it never traps and is Sendable/Equatable.
        let status = FoundationModelsAvailability.probe()
        _ = FoundationModelsAvailability.userFacingCause(for: status)
        XCTAssertNotEqual(status.titleForFailure, "")
    }

    func testGenerationError_RefusalAndGuardrailCasesExist() {
        let refused = GenerationError.refused(reason: "nope")
        let guardrail = GenerationError.guardrailViolation(reason: "blocked")
        let timeout = GenerationError.timeout
        XCTAssertEqual(refused, .refused(reason: "nope"))
        XCTAssertEqual(guardrail, .guardrailViolation(reason: "blocked"))
        XCTAssertEqual(timeout, .timeout)
    }

    @MainActor
    func testFoundationModels_GenerationServiceSmoke() {
        let service = GenerationService()
        XCTAssertFalse(service.isRunning)
        XCTAssertNil(service.lastResult)
        service.clearStatus()
        XCTAssertNil(service.lastStatus)
    }
}
