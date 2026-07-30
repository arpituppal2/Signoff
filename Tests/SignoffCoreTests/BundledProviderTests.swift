import XCTest
@testable import SignoffCore

/// Spec §3: Foundation Models only. Bundled phrase pools removed.
/// These tests verify the FM-only architecture and prompt template loading.
final class BundledProviderTests: XCTestCase {

    func testPromptTemplates_AllBucketsDecode() {
        let buckets = [BucketID.standard, .professional, .unhinged, .custom, .list, .footer]
        for bid in buckets {
            let loaded = PromptTemplate.load(bucket: bid.rawValue)
            XCTAssertNotNil(loaded, "Expected Prompt for bucket \(bid.rawValue)")
            XCTAssertFalse(loaded?.system.isEmpty ?? true)
            XCTAssertFalse(loaded?.rules.isEmpty ?? true)
        }
    }

    func testStandardPrompt_HasSystemInstructions() {
        guard let template = PromptTemplate.load(bucket: BucketID.standard.rawValue) else {
            XCTFail("Standard prompt must load")
            return
        }
        XCTAssertFalse(template.system.isEmpty)
        XCTAssertFalse(template.rules.isEmpty)
        XCTAssertFalse(template.userVariants.isEmpty)
        XCTAssertFalse(template.positiveExamples.isEmpty)
        XCTAssertFalse(template.negativeExamples.isEmpty)
    }

    func testPromptTemplate_FallbackIsAvailable() {
        let fallback = PromptTemplate.fallback
        XCTAssertFalse(fallback.system.isEmpty)
        XCTAssertGreaterThanOrEqual(fallback.rules.count, 3)
    }

    /// Verify the standard bucket maps to the "general" prompt resource
    func testStandardBucketMapsToGeneralResource() {
        let standard = PromptTemplate.load(bucket: BucketID.standard.rawValue)
        let general = PromptTemplate.load(bucket: "general")
        XCTAssertEqual(standard, general)
    }

    func testPromptTemplate_LoadUnknownBucketReturnsNil() {
        XCTAssertNil(PromptTemplate.load(bucket: "nonexistent-bucket"))
        XCTAssertNil(PromptTemplate.load(bucket: ""))
    }

    func testFoundationModelsAvailability_ProbeDoesNotTrap() {
        let status = FoundationModelsAvailability.probe()
        let cause = FoundationModelsAvailability.userFacingCause(for: status)
        XCTAssertFalse(cause.isEmpty)
        XCTAssertFalse(status.titleForFailure.isEmpty)
    }

    func testFoundationModelsAvailability_UserFacingCauses() {
        let cases: [FoundationModelsAvailability.Status] = [
            .available, .deviceNotEligible, .appleIntelligenceNotEnabled,
            .modelNotReady, .unavailable("test"), .unsupportedSDK,
        ]
        for status in cases {
            let cause = FoundationModelsAvailability.userFacingCause(for: status)
            XCTAssertFalse(cause.isEmpty, "Cause empty for \(status)")
        }
    }
}
