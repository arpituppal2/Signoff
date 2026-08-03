import XCTest
import Foundation
@testable import SignoffCore

/// Tests for the FM-only GenerationService. Spec §3: Foundation Models only.
@MainActor
final class GenerationTests: XCTestCase {

    // MARK: - Provider kind

    func testProviderKind_IsOnDeviceAI() {
        XCTAssertEqual(GenerationProviderKind.foundationModels.badgeTitle, "On-device")
        XCTAssertEqual(GenerationProviderKind.foundationModels.badgeSystemImage, "lock.fill")
        XCTAssertEqual(GenerationProviderKind.foundationModels.rawValue, "fmf")
    }

    func testProviderKind_SingleCaseOnly() {
        let all = GenerationProviderKind.allCases
        XCTAssertEqual(all, [.foundationModels])
        XCTAssertTrue(GenerationProviderKind.foundationModels.isLiveOnDevice)
    }

    // MARK: - GenerationService public surface (smoke)

    func testGenerationService_StartsNotRunning() {
        let service = GenerationService()
        XCTAssertFalse(service.isRunning)
    }

    func testGenerationService_LastResultIsReadable() {
        let service = GenerationService()
        XCTAssertNil(service.lastResult)
    }

    func testGenerationService_ClearStatus() {
        let service = GenerationService()
        XCTAssertNil(service.lastStatus)
        service.clearStatus()
        XCTAssertNil(service.lastStatus)
    }

    func testGenerationService_WarmupDoesNotCrash() async {
        let service = GenerationService()
        await service.warmup()
        XCTAssertNotNil(service)
    }

    // MARK: - PostProcessor

    func testEnsurePunctuation_AppendsPeriod() {
        XCTAssertEqual(PostProcessor.ensurePunctuation("Thanks"), "Thanks.")
    }

    func testEnsurePunctuation_PreservesExclamation() {
        XCTAssertEqual(PostProcessor.ensurePunctuation("Great!"), "Great!")
    }

    func testEnsurePunctuation_EmptyString() {
        XCTAssertEqual(PostProcessor.ensurePunctuation(""), "")
    }

    func testEnsurePunctuation_TrimsWhitespace() {
        XCTAssertEqual(PostProcessor.ensurePunctuation("  Talk soon  "), "Talk soon.")
    }

    func testAppendFooter_Nothing() {
        let snapshot = UserProfileSnapshot(profile: nil)
        XCTAssertEqual(PostProcessor.appendFooter("Thanks.", profile: snapshot, mode: .nothing), "Thanks.")
    }

    func testAppendFooter_Name() {
        let profile = UserProfile(name: "Alex")
        let snapshot = UserProfileSnapshot(profile: profile)
        let result = PostProcessor.appendFooter("Thanks.", profile: snapshot, mode: .name)
        XCTAssertTrue(result.contains("Thanks."))
        XCTAssertTrue(result.contains("—Alex"))
    }

    func testAppendFooter_FullFooter() {
        let profile = UserProfile(name: "Alex", title: "Engineer", company: "Acme", email: "alex@acme.com")
        let snapshot = UserProfileSnapshot(profile: profile)
        let result = PostProcessor.appendFooter("Thanks.", profile: snapshot, mode: .fullFooter)
        XCTAssertTrue(result.contains("Thanks."))
        XCTAssertTrue(result.contains("Alex"))
        XCTAssertTrue(result.contains("Engineer"))
        XCTAssertTrue(result.contains("Acme"))
        XCTAssertTrue(result.contains("alex@acme.com"))
    }

    // MARK: - FoundationModelsAvailability

    func testFoundationModelsAvailability_ProbeReturnsValidStatus() {
        // Should return a valid status without trapping.
        let status = FoundationModelsAvailability.probe()
        let validCases: [FoundationModelsAvailability.Status] = [
            .available, .deviceNotEligible, .appleIntelligenceNotEnabled,
            .modelNotReady, .unsupportedSDK
        ]
        XCTAssertTrue(validCases.contains(status), "Unexpected status: \(status)")
        XCTAssertFalse(status.titleForFailure.isEmpty)
    }

    func testFoundationModelsAvailability_TitleForFailure() {
        XCTAssertEqual(FoundationModelsAvailability.Status.unsupportedSDK.titleForFailure, "On-device model unavailable")
        XCTAssertEqual(FoundationModelsAvailability.Status.available.titleForFailure, "Apple Intelligence ready")
    }

    // MARK: - PromptTemplate

    func testPromptTemplate_LoadsStandard() {
        let template = PromptTemplate.load(bucket: "standard")
        XCTAssertNotNil(template)
        XCTAssertFalse(template?.system.isEmpty ?? true)
    }

    func testPromptTemplate_Fallback() {
        let fallback = PromptTemplate.fallback
        XCTAssertFalse(fallback.system.isEmpty)
        XCTAssertFalse(fallback.rules.isEmpty)
    }

    func testPromptTemplate_ChooseUser() {
        let template = PromptTemplate.fallback
        let user = template.chooseUser()
        XCTAssertFalse(user.isEmpty)
    }

    // MARK: - PromptComposer

    func testPromptComposer_ComposesWithoutCrash() {
        let template = PromptTemplate.fallback
        let snapshot = UserProfileSnapshot(profile: nil)
        let composed = PromptComposer.compose(template: template, profile: snapshot, recentTexts: [])
        XCTAssertFalse(composed.instructions.isEmpty)
        XCTAssertFalse(composed.prompt.isEmpty)
    }

    func testPromptComposer_IncludesProfile() {
        let profile = UserProfile(name: "Alex", selfDescription: "writes kindly")
        let snapshot = UserProfileSnapshot(profile: profile)
        let template = PromptTemplate.fallback
        let composed = PromptComposer.compose(template: template, profile: snapshot, recentTexts: [])
        XCTAssertTrue(composed.prompt.contains("writes kindly") || composed.instructions.contains("writes kindly"))
    }

    func testPromptComposer_AvoidsRecent() {
        let template = PromptTemplate.fallback
        let snapshot = UserProfileSnapshot(profile: nil)
        let composed = PromptComposer.compose(template: template, profile: snapshot, recentTexts: ["Talk soon."])
        XCTAssertFalse(composed.prompt.isEmpty)
    }

    // MARK: - UserProfileSnapshot

    func testUserProfileSnapshot_Empty() {
        let snapshot = UserProfileSnapshot(profile: nil)
        XCTAssertEqual(snapshot.name, "")
        XCTAssertNil(snapshot.title)
        XCTAssertNil(snapshot.company)
        XCTAssertEqual(snapshot.selfDescription, "")
        XCTAssertFalse(snapshot.emojiEnabled)
    }

    func testUserProfileSnapshot_WithProfile() {
        let profile = UserProfile(name: "Alex", title: "Eng", company: "Co", email: "a@c.com", phone: "555", website: "a.co", selfDescription: "friendly", emojiEnabled: true)
        let snapshot = UserProfileSnapshot(profile: profile)
        XCTAssertEqual(snapshot.name, "Alex")
        XCTAssertEqual(snapshot.title, "Eng")
        XCTAssertEqual(snapshot.company, "Co")
        XCTAssertEqual(snapshot.email, "a@c.com")
        XCTAssertEqual(snapshot.phone, "555")
        XCTAssertEqual(snapshot.website, "a.co")
        XCTAssertEqual(snapshot.selfDescription, "friendly")
        XCTAssertTrue(snapshot.emojiEnabled)
    }
}