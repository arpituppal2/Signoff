import Testing
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
struct OnboardingStateTests {

    @Test("Onboarding defaults hasCompletedOnboarding is false on fresh install")
    func onboardingDefaultsHasCompletedOnboardingIsFalseOnFreshInstall() {
        let fresh = AppSettings()
        #expect(fresh.hasCompletedOnboarding == false, "Fresh installs must have hasCompletedOnboarding=false (SPEC §6)")
    }

    @Test("Onboarding advance walks all four steps")
    func onboardingAdvanceWalksAllFourSteps() {
        let flow = OnboardingFlow(initial: .welcome)
        #expect(flow.currentStep == .welcome)
        flow.advance()
        #expect(flow.currentStep == .permissions)
        flow.advance()
        #expect(flow.currentStep == .profile)
        flow.advance()
        #expect(flow.currentStep == .cheatSheet)
        // Advancing past the final step auto-completes the flow.
        flow.advance()
        #expect(flow.isComplete == true, "Advancing past cheatSheet must mark isComplete=true")
    }

    @Test("Onboarding advance is noop once complete")
    func onboardingAdvanceIsNoopOnceComplete() {
        let flow = OnboardingFlow(initial: .cheatSheet)
        flow.complete()
        #expect(flow.isComplete == true)
        flow.advance()
        #expect(flow.isComplete == true, "advance() must not un-complete an already-completed flow")
        #expect(flow.currentStep == .cheatSheet, "advance() on a complete flow stays on the final step")
    }

    @Test("Onboarding skipping mid flow still marks complete")
    func onboardingSkippingMidFlowStillMarksComplete() {
        let flow = OnboardingFlow(initial: .welcome)
        flow.advance()
        #expect(flow.currentStep == .permissions)
        flow.skip()
        #expect(flow.isComplete == true, "Skip should still mark onboarding complete per SPEC §6")
    }

    @Test("Onboarding re-trigger from settings resets flow")
    func onboardingReTriggerFromSettingsResetsFlow() {
        // DX-EXP-6: re-onboarding button posts notification, consuming code
        // calls reset() to drop the user back to Welcome.
        let flow = OnboardingFlow(initial: .cheatSheet)
        flow.complete()
        #expect(flow.isComplete == true)
        flow.reset()
        #expect(flow.isComplete == false)
        #expect(flow.currentStep == .welcome)
    }

    @Test("Onboarding back button drops one step no wraparound")
    func onboardingBackButtonDropsOneStepNoWraparound() {
        let flow = OnboardingFlow(initial: .permissions)
        #expect(flow.currentStep == .permissions)
        flow.back()
        #expect(flow.currentStep == .welcome)
        flow.back()
        #expect(flow.currentStep == .welcome, "Back at the start must stay at Welcome (no wrap-around)")
    }

    @Test("Onboarding back is noop once complete")
    func onboardingBackIsNoopOnceComplete() {
        let flow = OnboardingFlow(initial: .welcome)
        flow.complete()
        flow.back()
        #expect(flow.isComplete == true, "back() must not un-complete a completed flow")
    }

    @Test("Onboarding step coordinator designated init binds flow")
    func onboardingStepCoordinatorDesignatedInitBindsFlow() {
        let flow = OnboardingFlow(initial: .welcome)
        let coordinator = OnboardingStepCoordinator(step: .welcome,
                                                     flow: flow,
                                                     appState: AppState.shared)
        #expect(coordinator.step == .welcome)
        #expect(coordinator.flow === flow, "Coordinator must hold a reference to the same OnboardingFlow instance")
    }

    @Test("Onboarding step coordinator convenience init builds implicit flow")
    func onboardingStepCoordinatorConvenienceInitBuildsImplicitFlow() {
        // The convenience init builds a fresh OnboardingFlow(initial: step)
        // so a single step's view can wire without the floating-panel owner.
        let coordinator = OnboardingStepCoordinator(step: .profile,
                                                     appState: AppState.shared)
        #expect(coordinator.step == .profile)
        #expect(coordinator.flow.currentStep == .profile, "Convenience init must bind the implicit flow's currentStep")
    }

    @Test("Onboarding step index matches order")
    func onboardingStepIndexMatchesOrder() {
        // OnboardingStep.index drives the advance/back math; assert the
        // SPEC §6 ordering is preserved (Welcome < Permissions < Profile < CheatSheet).
        #expect(OnboardingStep.welcome.index < OnboardingStep.permissions.index)
        #expect(OnboardingStep.permissions.index < OnboardingStep.profile.index)
        #expect(OnboardingStep.profile.index < OnboardingStep.cheatSheet.index)
    }

    // MARK: - hasCompletedOnboarding persistence

    @Test("Complete onboarding persists hasCompletedFlag")
    func completeOnboardingPersistsHasCompletedFlag() throws {
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
        #expect(flow.isComplete == true)

        // Production path: OnboardingWindowController.finishOnboarding →
        // AppState.markOnboardingCompleted() once the flow marks isComplete.
        AppState.shared.markOnboardingCompleted()

        #expect(AppState.shared.settings.hasCompletedOnboarding == true)
        #expect(AppState.shared.showOnboarding == false)

        let reloaded = try PersistenceController.shared.fetchSettings()
        #expect(reloaded.hasCompletedOnboarding == true, "hasCompletedOnboarding must survive a SwiftData reload")
    }

    @Test("Reset onboarding for replay clears persisted flag")
    func resetOnboardingForReplayClearsPersistedFlag() throws {
        try PersistenceController.shared.ensureSettings()
        let settings = try PersistenceController.shared.fetchSettings()
        settings.hasCompletedOnboarding = true
        try PersistenceController.shared.context.save()
        AppState.shared.settings = settings
        AppState.shared.showOnboarding = false

        AppState.shared.resetOnboardingForReplay()

        #expect(AppState.shared.settings.hasCompletedOnboarding == false)
        #expect(AppState.shared.showOnboarding == true)

        let reloaded = try PersistenceController.shared.fetchSettings()
        #expect(reloaded.hasCompletedOnboarding == false, "Replay must clear the persisted completion flag")
    }

    @Test("Onboarding flow complete then AppState persist round trips")
    func onboardingFlowCompleteThenAppStatePersistRoundTrips() throws {
        // End-to-end state machine: advance to Done → complete → persist.
        let flow = OnboardingFlow(initial: .welcome)
        flow.advance() // permissions
        flow.advance() // profile
        flow.advance() // cheatSheet
        flow.complete()
        #expect(flow.isComplete == true)

        try PersistenceController.shared.ensureSettings()
        AppState.shared.settings = try PersistenceController.shared.fetchSettings()
        AppState.shared.markOnboardingCompleted()

        #expect(AppState.shared.settings.hasCompletedOnboarding == true)
        #expect(flow.currentStep == .cheatSheet)
    }

    @Test("Sync onboarding flag from settings mirrors persisted flag")
    func syncOnboardingFlagFromSettingsMirrorsPersistedFlag() throws {
        try PersistenceController.shared.ensureSettings()
        let settings = try PersistenceController.shared.fetchSettings()
        AppState.shared.settings = settings

        settings.hasCompletedOnboarding = false
        AppState.shared.syncOnboardingFlagFromSettings()
        #expect(AppState.shared.showOnboarding == true, "Incomplete onboarding must drive showOnboarding=true")

        settings.hasCompletedOnboarding = true
        AppState.shared.syncOnboardingFlagFromSettings()
        #expect(AppState.shared.showOnboarding == false, "Completed onboarding must drive showOnboarding=false")
    }

    @Test("Mark onboarding completed is idempotent")
    func markOnboardingCompletedIsIdempotent() throws {
        try PersistenceController.shared.ensureSettings()
        let settings = try PersistenceController.shared.fetchSettings()
        settings.hasCompletedOnboarding = false
        try PersistenceController.shared.context.save()
        AppState.shared.settings = settings

        AppState.shared.markOnboardingCompleted()
        AppState.shared.markOnboardingCompleted()

        #expect(AppState.shared.settings.hasCompletedOnboarding == true)
        #expect(AppState.shared.showOnboarding == false)
        let reloaded = try PersistenceController.shared.fetchSettings()
        #expect(reloaded.hasCompletedOnboarding == true)
    }
}