import Foundation

/// App is free and open source. All features are available to everyone.
/// No licensing, no Pro tiers, no quotas.
@MainActor
public final class EntitlementManager: ObservableObject {
    public static let shared = EntitlementManager()

    /// Everything is always available — no gating.
    @Published public private(set) var lastUpdated: Date = Date()

    public init() {}

    public var isPro: Bool { true }
    public var generationsQuota: Int? { nil }

    /// All buckets are always allowed.
    public func bucketAllowed(_ bucketId: String) -> Bool { true }
}

public extension Notification.Name {
    static let entitlementsDidChange = Notification.Name("com.signoff.entitlementsDidChange")
    static let showDegradedEntitlement = Notification.Name("com.signoff.showDegradedEntitlement")
    static let bucketShortcutTriggered = Notification.Name("com.signoff.bucketShortcutTriggered")
    static let regnerateSignoffShortcutTriggered = Notification.Name("com.signoff.regenerateShortcutTriggered")
    static let openSettingsShortcutTriggered = Notification.Name("com.signoff.openSettingsShortcut")
    static let openHUDShortcutTriggered = Notification.Name("com.signoff.openHUDShortcut")
    static let shortcutTapFailed = Notification.Name("com.signoff.shortcutTapFailed")
}
