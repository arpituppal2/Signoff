import Foundation

/// Tracks generation count for display purposes only. Signoff is free — no
/// limits, no tiers, no quotas. This exists purely so the popover status
/// line can show how many signoffs you've drafted.
public final class UsageTracker: @unchecked Sendable {
    public static let shared = UsageTracker()

    private init() {}

    private let countKey = "com.signoff.usage.count"

    public var currentCount: Int {
        get { UserDefaults.standard.integer(forKey: countKey) }
        set { UserDefaults.standard.set(newValue, forKey: countKey) }
    }

    public func increment() {
        currentCount = currentCount + 1
    }

    public func reset() {
        currentCount = 0
    }
}