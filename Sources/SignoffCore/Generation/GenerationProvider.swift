import Foundation

/// How the last generation was produced. Signoff is **on-device only**: every
/// phrase is drafted by Apple Foundation Models running locally — there is no
/// offline phrasebook, no canned pool, and nothing ever leaves the Mac. If the
/// on-device model isn't ready, generation simply fails honestly rather than
/// serving something pre-written.
public enum GenerationProviderKind: String, Codable, Sendable, CaseIterable {
    /// Live Apple Foundation Models (on-device). The only provider — and the
    /// only path that exists in this app.
    case foundationModels = "fmf"

    public var badgeTitle: String {
        switch self {
        case .foundationModels: return "On-device"
        }
    }

    public var badgeSystemImage: String {
        switch self {
        case .foundationModels: return "lock.fill"
        }
    }

    /// True for the live on-device model path. Always true here — there is no
    /// other path — but kept for callers that branch on it.
    public var isLiveOnDevice: Bool { self == .foundationModels }
}
