import Foundation

/// How the last generation was produced. Today the shipping path is
/// on-device-only (Apple Foundation Models); the cloud kinds exist for the
/// ProviderBench harness and the cloud-primary rollout described in
/// docs/CLOUD_PLAN.md. Persisted records may carry any raw value, so the enum
/// stays Codable with string rawValues.
public enum GenerationProviderKind: String, Codable, Sendable, CaseIterable {
    /// Live Apple Foundation Models (on-device).
    case foundationModels = "fmf"
    /// OpenAI chat completions (cloud).
    case openAI = "openai"
    /// Anthropic messages API (cloud).
    case anthropic = "anthropic"

    public var badgeTitle: String {
        switch self {
        case .foundationModels: return "On-device"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        }
    }

    public var badgeSystemImage: String {
        switch self {
        case .foundationModels: return "lock.fill"
        case .openAI, .anthropic: return "cloud.fill"
        }
    }

    /// True for the live on-device model path.
    public var isLiveOnDevice: Bool { self == .foundationModels }

    /// True for network-backed providers (gated by quota/licensing later).
    public var isCloud: Bool { self != .foundationModels }
}
