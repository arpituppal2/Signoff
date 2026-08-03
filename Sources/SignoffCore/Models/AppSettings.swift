import Foundation
import SwiftData

@Model
public final class AppSettings {
    public var popoverWidth: Double
    public var colorSchemeRaw: String
    public var showShortcutHints: Bool
    public var hasCompletedOnboarding: Bool
    public var hasSeenQuickStart: Bool
    public var dismissedQuickStart: Bool

    /// The user's generation, steering on-device voice (anti-cringe lever).
    /// Optional + resolved via `AgeGroup.resolve` so an existing store migrates
    /// cleanly (nil → default Gen Z) without a schema bump crashing launch.
    public var generationAgeGroupRaw: String?
    /// Onboarding schema version last shown to this store. Bumping
    /// `AppState.requiredOnboardingVersion` re-shows the tour once for existing
    /// users so major redesigns can re-introduce themselves.
    public var onboardingVersionSeen: Int?

    public var bucketShortcutsJSON: String
    public var launchAtLogin: Bool
    public var verboseLogging: Bool
    /// HIG status-bar apps: users must be able to hide the menu bar extra.
    /// Default `true`. When `false`, Quit lives in Settings → General; Settings
    /// stays reachable via `SettingsSceneOpener` / app reopen / ⌘, while frontmost.
    public var showsStatusItem: Bool = true

    public var createdAt: Date
    public var updatedAt: Date

    public init(popoverWidth: Double,
                colorSchemeRaw: String,
                showShortcutHints: Bool,
                hasCompletedOnboarding: Bool,
                hasSeenQuickStart: Bool,
                dismissedQuickStart: Bool,
                launchAtLogin: Bool,
                verboseLogging: Bool,
                showsStatusItem: Bool,
                bucketShortcutsJSON: String) {
        self.popoverWidth = popoverWidth
        self.colorSchemeRaw = colorSchemeRaw
        self.showShortcutHints = showShortcutHints
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.hasSeenQuickStart = hasSeenQuickStart
        self.dismissedQuickStart = dismissedQuickStart
        self.bucketShortcutsJSON = bucketShortcutsJSON
        self.launchAtLogin = launchAtLogin
        self.verboseLogging = verboseLogging
        self.showsStatusItem = showsStatusItem
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }

    public convenience init() {
        self.init(popoverWidth: 380,
                  colorSchemeRaw: "system",
                  showShortcutHints: true,
                  hasCompletedOnboarding: false,
                  hasSeenQuickStart: false,
                  dismissedQuickStart: false,
                  launchAtLogin: false,
                  verboseLogging: false,
                  showsStatusItem: true,
                  bucketShortcutsJSON: AppSettings.defaultBucketShortcutsJSON)
    }

    /// Resolved writer generation (defaults to Gen Z when unset or unknown).
    public var generationAgeGroup: AgeGroup {
        get { AgeGroup.resolve(generationAgeGroupRaw) }
        set { generationAgeGroupRaw = newValue.rawValue }
    }

    /// Matches `ShortcutManager.defaults()`: Normal=1, Professional=2,
    /// Cynical=3, Custom=4 (v3 bucket slim / v3.5 naming).
    public static let defaultBucketShortcutsJSON: String = {
        let pairs = [
            ("standard", "1"), ("professional", "2"), ("unhinged", "3"),
            ("custom", "4"),
        ]
        let encoded = pairs.map { "{\"bucketId\":\"\($0.0)\",\"digitKey\":\"\($0.1)\",\"modifier\":\"cmdCtrl\"}" }.joined(separator: ",")
        return "[\(encoded)]"
    }()
}
