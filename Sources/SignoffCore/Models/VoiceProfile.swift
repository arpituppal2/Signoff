import Foundation
import SwiftData

/// Minimal VoiceProfile — no learning, no fingerprinting.
/// Kept only for SwiftData migration compatibility and PromptComposer.VoiceProfileSnapshot.
@Model
public final class VoiceProfile {
    @Attribute(.unique) public var id: String = "primary"
    public var learningConsentGranted: Bool = false
    public var lastUpdated: Date = Date()

    public init() {}
}

@MainActor
public extension VoiceProfile {
    static let shared: VoiceProfile = {
        VoiceProfile()
    }()

    static func initialize() {
        // No-op: learning disabled
    }
}

public extension VoiceProfile {
    /// Sendable snapshot with no learning data — always empty/nil.
    var discriminativeFingerprint: [String: Double] { [:] }
    var noiseLexicalFingerprint: [String: Double] { [:] }
    var qualityPromptSummary: String { "" }
    var adoptedSignoffPatterns: [String] { [] }
    var rejectedSignoffPatterns: [String] { [] }
}