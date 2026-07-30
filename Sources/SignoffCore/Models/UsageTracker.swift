import Foundation
import SwiftData

/// Tracks signoff generation usage across free and paid tiers.
/// Free users get 100 signoffs. Paid users get unlimited.
public final class UsageTracker: @unchecked Sendable {
    public static let shared = UsageTracker()
    
    private init() {}
    
    public enum Tier: String, Codable, Sendable, Equatable {
        case free
        case monthly       // $1/month
        case yearly        // $10/year
        case lifetime      // $30/lifetime
    }
    
    public struct Subscription: Codable, Sendable, Equatable {
        public var tier: Tier
        public var stripeCustomerId: String?
        public var stripeSubscriptionId: String?
        public var activatedAt: Date?
        public var expiresAt: Date?
        public var isActive: Bool
        
        public static let free = Subscription(tier: .free, isActive: true)
        
        public init(tier: Tier, stripeCustomerId: String? = nil, stripeSubscriptionId: String? = nil, activatedAt: Date? = nil, expiresAt: Date? = nil, isActive: Bool = true) {
            self.tier = tier
            self.stripeCustomerId = stripeCustomerId
            self.stripeSubscriptionId = stripeSubscriptionId
            self.activatedAt = activatedAt
            self.expiresAt = expiresAt
            self.isActive = isActive
        }
    }
    
    public static let freeLimit = 100
    private let countKey = "com.signoff.usage.count"
    private let subscriptionKey = "com.signoff.usage.subscription"
    
    public var currentCount: Int {
        get { UserDefaults.standard.integer(forKey: countKey) }
        set { UserDefaults.standard.set(newValue, forKey: countKey) }
    }
    
    public var subscription: Subscription {
        get {
            guard let data = UserDefaults.standard.data(forKey: subscriptionKey),
                  let sub = try? JSONDecoder().decode(Subscription.self, from: data) else {
                return .free
            }
            return sub
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: subscriptionKey)
            }
        }
    }
    
    public var remainingFreeCount: Int {
        max(0, Self.freeLimit - currentCount)
    }
    
    public var canGenerate: Bool {
        if subscription.isActive && subscription.tier != .free { return true }
        return currentCount < Self.freeLimit
    }
    
    public var isOnPaidTier: Bool {
        subscription.isActive && subscription.tier != .free
    }
    
    public func incrementCount() {
        guard subscription.tier == .free || !subscription.isActive else { return }
        currentCount = currentCount + 1
    }
    
    public func resetCount() {
        currentCount = 0
    }
    
    // MARK: - Pricing
    
    public static let monthlyPrice: Int = 1      // $1/month
    public static let yearlyPrice: Int = 10       // $10/year
    public static let lifetimePrice: Int = 30     // $30/lifetime
    
    public static let monthlyPriceId = "price_1_monthly"  // Replace with actual Stripe price IDs
    public static let yearlyPriceId = "price_1_yearly"
    public static let lifetimePriceId = "price_1_lifetime"
    
    public static var pricingDisplay: [(tier: Tier, label: String, price: String, period: String)] {
        [
            (.monthly, "Monthly", "$\(monthlyPrice)", "/month"),
            (.yearly, "Yearly", "$\(yearlyPrice)", "/year"),
            (.lifetime, "Lifetime", "$\(lifetimePrice)", "once"),
        ]
    }
}
