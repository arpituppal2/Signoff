import Testing
import Foundation
@testable import SignoffCore

/// Spec §3: Foundation Models only. Bundled phrase pools removed.
/// These tests verify the FM-only architecture and prompt template loading.
struct BundledProviderTests {

    @Test("Prompt templates all buckets decode")
    func promptTemplatesAllBucketsDecode() async throws {
        let buckets = [BucketID.standard, .professional, .unhinged]
        for bid in buckets {
            let loaded = await PromptTemplate.load(bucket: bid.rawValue)
            #expect(loaded != nil, "Expected Prompt for bucket \(bid.rawValue)")
            if let loaded = loaded {
                #expect(!loaded.system.isEmpty, "system empty for \(bid.rawValue): \(loaded.system)")
                #expect(!loaded.userVariants.isEmpty, "userVariants empty for \(bid.rawValue)")
            }
        }
    }

    @Test("Standard prompt has system instructions")
    func standardPromptHasSystemInstructions() async throws {
        guard let template = await PromptTemplate.load(bucket: BucketID.standard.rawValue) else {
            Issue.record("Standard prompt must load")
            return
        }
        #expect(!template.system.isEmpty)
        #expect(!template.userVariants.isEmpty)
        #expect(template.positiveExamples != nil)
    }

    @Test("Prompt template fallback is available")
    func promptTemplateFallbackIsAvailable() {
        let fallback = PromptTemplate.fallback
        #expect(!fallback.system.isEmpty)
        #expect(fallback.userVariants.count >= 1)
    }

    /// Verify the standard bucket maps to the "general" prompt resource
    @Test("Standard bucket maps to general resource")
    func standardBucketMapsToGeneralResource() async throws {
        let standard = await PromptTemplate.load(bucket: BucketID.standard.rawValue)
        let general = await PromptTemplate.load(bucket: "general")
        #expect(standard == general)
    }

    @Test("Prompt template load unknown bucket returns nil")
    func promptTemplateLoadUnknownBucketReturnsNil() async throws {
        #expect(await PromptTemplate.load(bucket: "nonexistent-bucket") == nil)
        #expect(await PromptTemplate.load(bucket: "") == nil)
    }

    @Test("Foundation Models availability probe does not trap")
    func foundationModelsAvailabilityProbeDoesNotTrap() {
        let status = FoundationModelsAvailability.probe()
        let cause = FoundationModelsAvailability.userFacingCause(for: status)
        #expect(!cause.isEmpty)
        #expect(!status.titleForFailure.isEmpty)
    }

    @Test("Foundation Models availability user facing causes")
    func foundationModelsAvailabilityUserFacingCauses() {
        let cases: [FoundationModelsAvailability.Status] = [
            .available, .deviceNotEligible, .appleIntelligenceNotEnabled,
            .modelNotReady, .unavailable("test"), .unsupportedSDK,
        ]
        for status in cases {
            let cause = FoundationModelsAvailability.userFacingCause(for: status)
            #expect(!cause.isEmpty, "Cause empty for \(status)")
        }
    }
}