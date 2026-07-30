import XCTest
import Foundation
@testable import SignoffCore

/// Tests the Onboarding step flow: 4-step floating NSPanel's flow state
/// (`Welcome → Permissions → Profile → CheatSheet`), the `complete()` +
/// `reset()` interactions driven by DX-EXP-6, and the step-coordinator
/// facade. Per SPEC §6 + CEO EXPANSION §Temporal Interrogation H4 + DX
/// EXPANSION Pass 2. `OnboardingFlow` + `OnboardingStepCoordinator` are
/// real production types in `Sources/SignoffCore/Models/OnboardingFlow.swift`,
/// so every assertion here exercises the shipped implementation.
@MainActor
final class OnboardingStateTests: XCTestCase {

    func testOnboardingDefaults_HasCompletedIsFalseOnFreshInstall() {
        let fresh = AppSettings()
        XCTAssertFalse(fresh.hasCompletedOnboarding,
                       "Fresh installs must have hasCompletedOnboarding=false (SPEC §6)")
    }

    func testOnboarding_AdvanceWalksAllFourSteps() {
        let flow = OnboardingFlow(initial: .welcome)
        XCTAssertEqual(flow.currentStep, .welcome)
        flow.advance()
        XCTAssertEqual(flow.currentStep, .permissions)
        flow.advance()
        XCTAssertEqual(flow.currentStep, .profile)
        flow.advance()
        XCTAssertEqual(flow.currentStep, .cheatSheet)
        // Advancing past the final step auto-completes the flow.
        flow.advance()
        XCTAssertTrue(flow.isComplete,
                      "Advancing past cheatSheet must mark isComplete=true")
    }

    func testOnboarding_AdvanceIsNoopOnceComplete() {
        let flow = OnboardingFlow(initial: .cheatSheet)
        flow.complete()
        XCTAssertTrue(flow.isComplete)
        flow.advance()
        XCTAssertTrue(flow.isComplete,
                      "advance() must not un-complete an already-completed flow")
        XCTAssertEqual(flow.currentStep, .cheatSheet,
                       "advance() on a complete flow stays on the final step")
    }

    func testOnboarding_SkippingMidFlowStillMarksComplete() {
        let flow = OnboardingFlow(initial: .welcome)
        flow.advance()
        XCTAssertEqual(flow.currentStep, .permissions)
        flow.skip()
        XCTAssertTrue(flow.isComplete,
                      "Skip should still mark onboarding complete per SPEC §6")
    }

    func testOnboarding_ReTriggerFromSettingsResetsFlow() {
        // DX-EXP-6: re-onboarding button posts notification, consuming code
        // calls reset() to drop the user back to Welcome.
        let flow = OnboardingFlow(initial: .cheatSheet)
        flow.complete()
        XCTAssertTrue(flow.isComplete)
        flow.reset()
        XCTAssertFalse(flow.isComplete)
        XCTAssertEqual(flow.currentStep, .welcome)
    }

    func testOnboarding_BackButtonDropsOneStepNoWraparound() {
        let flow = OnboardingFlow(initial: .permissions)
        XCTAssertEqual(flow.currentStep, .permissions)
        flow.back()
        XCTAssertEqual(flow.currentStep, .welcome)
        flow.back()
        XCTAssertEqual(flow.currentStep, .welcome,
                       "Back at the start must stay at Welcome (no wrap-around)")
    }

    func testOnboarding_BackIsNoopOnceComplete() {
        let flow = OnboardingFlow(initial: .welcome)
        flow.complete()
        flow.back()
        XCTAssertTrue(flow.isComplete,
                      "back() must not un-complete a completed flow")
    }

    func testOnboardingStepCoordinator_DesignatedInitBindsFlow() {
        let flow = OnboardingFlow(initial: .welcome)
        let coordinator = OnboardingStepCoordinator(step: .welcome,
                                                     flow: flow,
                                                     appState: AppState.shared)
        XCTAssertEqual(coordinator.step, .welcome)
        XCTAssertTrue(coordinator.flow === flow,
                      "Coordinator must hold a reference to the same OnboardingFlow instance")
    }

    func testOnboardingStepCoordinator_ConvenienceInitBuildsImplicitFlow() {
        // The convenience init builds a fresh OnboardingFlow(initial: step)
        // so a single step's view can wire without the floating-panel owner.
        let coordinator = OnboardingStepCoordinator(step: .profile,
                                                     appState: AppState.shared)
        XCTAssertEqual(coordinator.step, .profile)
        XCTAssertEqual(coordinator.flow.currentStep, .profile,
                       "Convenience init must bind the implicit flow's currentStep")
    }

    func testOnboardingStep_StepIndexMatchesOrder() {
        // OnboardingStep.index drives the advance/back math; assert the
        // SPEC §6 ordering is preserved (Welcome < Permissions < Profile < CheatSheet).
        XCTAssertLessThan(OnboardingStep.welcome.index,     OnboardingStep.permissions.index)
        XCTAssertLessThan(OnboardingStep.permissions.index, OnboardingStep.profile.index)
        XCTAssertLessThan(OnboardingStep.profile.index,     OnboardingStep.cheatSheet.index)
    }

    // MARK: - hasCompletedOnboarding persistence

    func testCompleteOnboarding_PersistsHasCompletedFlag() throws {
        try PersistenceController.shared.ensureSettings()
        let settings = try PersistenceController.shared.fetchSettings()
        settings.hasCompletedOnboarding = false
        settings.updatedAt = Date()
        try PersistenceController.shared.context.save()

        // Mirror first-run: AppState holds the same SwiftData row.
        AppState.shared.settings = settings
        AppState.shared.showOnboarding = true

        let flow = OnboardingFlow(initial: .cheatSheet)
        flow.complete()
        XCTAssertTrue(flow.isComplete)

        // Production path: OnboardingWindowController.finishOnboarding →
        // AppState.markOnboardingCompleted() once the flow marks isComplete.
        AppState.shared.markOnboardingCompleted()

        XCTAssertTrue(AppState.shared.settings.hasCompletedOnboarding)
        XCTAssertFalse(AppState.shared.showOnboarding)

        let reloaded = try PersistenceController.shared.fetchSettings()
        XCTAssertTrue(reloaded.hasCompletedOnboarding,
                      "hasCompletedOnboarding must survive a SwiftData reload")
    }

    func testResetOnboardingForReplay_ClearsPersistedFlag() throws {
        try PersistenceController.shared.ensureSettings()
        let settings = try PersistenceController.shared.fetchSettings()
        settings.hasCompletedOnboarding = true
        try PersistenceController.shared.context.save()
        AppState.shared.settings = settings
        AppState.shared.showOnboarding = false

        AppState.shared.resetOnboardingForReplay()

        XCTAssertFalse(AppState.shared.settings.hasCompletedOnboarding)
        XCTAssertTrue(AppState.shared.showOnboarding)

        let reloaded = try PersistenceController.shared.fetchSettings()
        XCTAssertFalse(reloaded.hasCompletedOnboarding,
                       "Replay must clear the persisted completion flag")
    }

    func testOnboardingFlow_CompleteThenAppStatePersist_RoundTrips() throws {
        // End-to-end state machine: advance to Done → complete → persist.
        let flow = OnboardingFlow(initial: .welcome)
        flow.advance() // permissions
        flow.advance() // profile
        flow.advance() // cheatSheet
        flow.complete()
        XCTAssertTrue(flow.isComplete)

        try PersistenceController.shared.ensureSettings()
        AppState.shared.settings = try PersistenceController.shared.fetchSettings()
        AppState.shared.markOnboardingCompleted()

        XCTAssertTrue(AppState.shared.settings.hasCompletedOnboarding)
        XCTAssertEqual(flow.currentStep, .cheatSheet)
    }

    func testSyncOnboardingFlagFromSettings_MirrorsPersistedFlag() throws {
        try PersistenceController.shared.ensureSettings()
        let settings = try PersistenceController.shared.fetchSettings()
        AppState.shared.settings = settings

        settings.hasCompletedOnboarding = false
        AppState.shared.syncOnboardingFlagFromSettings()
        XCTAssertTrue(AppState.shared.showOnboarding,
                      "Incomplete onboarding must drive showOnboarding=true")

        settings.hasCompletedOnboarding = true
        AppState.shared.syncOnboardingFlagFromSettings()
        XCTAssertFalse(AppState.shared.showOnboarding,
                       "Completed onboarding must drive showOnboarding=false")
    }

    func testMarkOnboardingCompleted_IsIdempotent() throws {
        try PersistenceController.shared.ensureSettings()
        let settings = try PersistenceController.shared.fetchSettings()
        settings.hasCompletedOnboarding = false
        try PersistenceController.shared.context.save()
        AppState.shared.settings = settings

        AppState.shared.markOnboardingCompleted()
        AppState.shared.markOnboardingCompleted()

        XCTAssertTrue(AppState.shared.settings.hasCompletedOnboarding)
        XCTAssertFalse(AppState.shared.showOnboarding)
        let reloaded = try PersistenceController.shared.fetchSettings()
        XCTAssertTrue(reloaded.hasCompletedOnboarding)
    }
}
