// OnboardingFlow.swift — simplified for single-panel onboarding.
// Keeps enum/case order for backward compatibility with OnboardingStateTests.

import Foundation

/// Steps preserved for enum-ordering tests. Actual onboarding is a single panel.
public enum OnboardingStep: String, CaseIterable, Identifiable, Equatable {
    case welcome
    case permissions
    case profile
    case cheatSheet
    public var id: String { rawValue }
    public var index: Int {
        switch self {
        case .welcome:      return 0
        case .permissions:  return 1
        case .profile:      return 2
        case .cheatSheet:   return 3
        }
    }
}

/// Minimal flow coordinator. The single-panel onboarding uses `markOnboardingCompleted()`
/// directly on AppState and does not instantiate this class.
@MainActor
public final class OnboardingFlow: ObservableObject {
    @Published public private(set) var currentStep: OnboardingStep
    @Published public private(set) var isComplete: Bool = false

    public init(initial: OnboardingStep = .welcome) {
        self.currentStep = initial
    }

    public func advance() {
        guard !isComplete else { return }
        let nextIndex = currentStep.index + 1
        if let next = OnboardingStep.allCases.first(where: { $0.index == nextIndex }) {
            currentStep = next
        } else {
            complete()
        }
    }

    public func back() {
        guard !isComplete, currentStep.index > 0 else { return }
        if let prev = OnboardingStep.allCases.first(where: { $0.index == currentStep.index - 1 }) {
            currentStep = prev
        }
    }

    public func skip() { complete() }
    public func complete() { isComplete = true }
    public func reset() {
        currentStep = .welcome
        isComplete = false
    }
}

@MainActor
public final class OnboardingStepCoordinator: ObservableObject {
    public let step: OnboardingStep
    public let flow: OnboardingFlow
    public let appState: AppState

    public init(step: OnboardingStep,
                flow: OnboardingFlow,
                appState: AppState) {
        self.step = step
        self.flow = flow
        self.appState = appState
    }

    public convenience init(step: OnboardingStep, appState: AppState) {
        self.init(step: step, flow: OnboardingFlow(initial: step), appState: appState)
    }
}
