import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Maps `SystemLanguageModel.default.availability` into a Signoff-facing status
/// that Settings / ErrorFixCard can publish without importing FoundationModels
/// at every call site.
@MainActor
public final class FoundationModelsAvailability: ObservableObject {
    public static let shared = FoundationModelsAvailability()

    public enum Status: Equatable, Sendable {
        case available
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
        case unavailable(String)
        /// SDK / OS does not expose Foundation Models (pre-macOS 26 or no module).
        case unsupportedSDK

        public var titleForFailure: String {
            switch self {
            case .available:
                return "Apple Intelligence ready"
            case .deviceNotEligible:
                return "This Mac doesn't support Apple Intelligence"
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence"
            case .modelNotReady:
                return "Apple Intelligence is still downloading"
            case .unavailable:
                return "Apple Intelligence unavailable"
            case .unsupportedSDK:
                return "On-device model unavailable"
            }
        }
    }

    @Published public private(set) var status: Status = .unsupportedSDK

    /// Deep-link into System Settings → Apple Intelligence & Siri (not Privacy & Security).
    /// `nonisolated` so ErrorFixCard / nonisolated call sites can read the constant
    /// without hopping onto MainActor (the URL itself is immutable).
    nonisolated public static let appleIntelligenceSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!

    public init() {
        refresh()
    }

    public var isUsable: Bool {
        if case .available = status { return true }
        return false
    }

    public var userFacingTitle: String { status.titleForFailure }

    public var userFacingCause: String {
        Self.userFacingCause(for: status)
    }

    /// Only `appleIntelligenceNotEnabled` should deep-link into System Settings
    /// → Apple Intelligence & Siri. Hardware / download / SDK gaps are
    /// informational — never send the user to Privacy & Security for FM.
    public var shouldOpenAppleIntelligenceSettings: Bool {
        Self.shouldOpenAppleIntelligenceSettings(for: status)
    }

    public func refresh() {
        status = Self.probe()
    }

    nonisolated public static func shouldOpenAppleIntelligenceSettings(for status: Status) -> Bool {
        if case .appleIntelligenceNotEnabled = status { return true }
        return false
    }

    /// Thread-safe snapshot for provider gates (no MainActor required).
    nonisolated public static func probe() -> Status {
#if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return map(SystemLanguageModel.default.availability)
        }
#endif
        return .unsupportedSDK
    }

    nonisolated public static func userFacingCause(for status: Status) -> String {
        switch status {
        case .available:
            return "Foundation Models are ready for private on-device generation."
        case .deviceNotEligible:
            return "Foundation Models require Apple Intelligence hardware (M-series Mac)."
        case .appleIntelligenceNotEnabled:
            return "Enable Apple Intelligence in System Settings → Apple Intelligence & Siri so Signoff can draft on-device."
        case .modelNotReady:
            return "Apple Intelligence is downloading or preparing the on-device model. Try again in a few minutes."
        case .unavailable(let reason):
            return reason
        case .unsupportedSDK:
            return "This build can't reach Foundation Models. Requires macOS 26+ with Apple Intelligence."
        }
    }

#if canImport(FoundationModels)
    @available(macOS 26, *)
    nonisolated public static func map(_ availability: SystemLanguageModel.Availability) -> Status {
        switch availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable(let other):
            return .unavailable(String(describing: other))
        @unknown default:
            return .unavailable("Unknown Foundation Models availability")
        }
    }
#endif
}
