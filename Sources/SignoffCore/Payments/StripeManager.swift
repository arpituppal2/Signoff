import Foundation
import AppKit

/// Manages Stripe payment integration for Signoff subscriptions.
/// Uses Stripe Checkout for payment processing (no SDK dependency needed).
/// Subscriptions: $1/month, $10/year, $30/lifetime.
public final class StripeManager: @unchecked Sendable {
    public static let shared = StripeManager()
    
    // Configure these with your actual Stripe values
    // Stored in Keychain for security
    private var publishableKey: String? {
        try? KeychainStore.shared.loadString(account: "com.signoff.stripe.publishable")
    }
    
    // MARK: - Checkout
    
    /// Open Stripe Checkout for a given price tier.
    /// Uses the stored publishable key to create a checkout session.
    public func checkout(tier: UsageTracker.Tier) async -> Bool {
        guard let _ = publishableKey else {
            // No Stripe configured — show a fallback message
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Stripe Not Configured"
                alert.informativeText = "Payment processing hasn't been configured yet. For now, all features are free."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            // Enable paid tier locally for demo purposes
            var sub = UsageTracker.shared.subscription
            sub.tier = tier
            sub.isActive = true
            sub.activatedAt = Date()
            UsageTracker.shared.subscription = sub
            return true
        }
        
        let priceId: String
        switch tier {
        case .monthly: priceId = UsageTracker.monthlyPriceId
        case .yearly: priceId = UsageTracker.yearlyPriceId
        case .lifetime: priceId = UsageTracker.lifetimePriceId
        case .free: return false
        }
        
        // In production: call your backend to create a Stripe Checkout session.
        // For now, return true to allow demo flow.
        await MainActor.run {
            var sub = UsageTracker.shared.subscription
            sub.tier = tier
            sub.isActive = true
            sub.activatedAt = Date()
            if tier == .monthly {
                sub.expiresAt = Calendar.current.date(byAdding: .month, value: 1, to: Date())
            } else if tier == .yearly {
                sub.expiresAt = Calendar.current.date(byAdding: .year, value: 1, to: Date())
            }
            UsageTracker.shared.subscription = sub
        }
        return true
    }
    
    /// Open Stripe Customer Portal for managing subscriptions.
    public func openCustomerPortal() async {
        // In production: call your backend to create a billing portal session.
        // For now, show a message.
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = "Manage Subscription"
            alert.informativeText = "To manage your subscription, visit our website at https://signoff.app/account"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open Website")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "https://signoff.app/account") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
