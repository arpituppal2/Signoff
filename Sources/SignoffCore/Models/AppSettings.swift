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

    /// When enabled, generating a signoff within the cooldown window replaces
    /// the previously-pasted one (selects it and pastes over) instead of
    /// appending at the cursor. Paired with `rapidReplaceCooldownSeconds`.
    public var rapidReplaceEnabled: Bool = true
    /// Seconds after a paste during which a retrigger replaces the previous pasted
    /// text. Options: 2, 3, 5, 10, 15, 30, 60. Default 3.
    public var rapidReplaceCooldownSeconds: Int = 3
    /// When enabled, shortcuts auto-paste (⌘V) at cursor; when disabled,
    /// shortcuts only copy to clipboard (manual ⌘V). Default true.
    public var shortcutAutoPaste: Bool = true
    /// Shortcut for "After Signoff Only" — pastes just the footer content.
    /// Serialized as JSON matching BucketBinding shape (digitKey + modifier).
    public var afterSignoffShortcutJSON: String = ""

    /// Serialized NSAttributedString appended after the generated signoff.
    /// Stored as Data so SwiftData can persist it; exposes a computed
    /// `afterSignoffAttributedString` for read/write and a `afterSignoffText`
    /// convenience for plain-text consumers.
    public var afterSignoffAttributedStringData: Data?

    /// Convenience: plain-text version (used by simple consumers / migrations).
    public var afterSignoffText: String {
        get {
            guard let data = afterSignoffAttributedStringData,
                  let attr = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data) else { return "" }
            return attr.string
        }
        set {
            let attr = NSMutableAttributedString(string: newValue)
            afterSignoffAttributedStringData = try? NSKeyedArchiver.archivedData(withRootObject: attr, requiringSecureCoding: false)
        }
    }

    /// The attributed string editor value, or an empty attributed string.
    public var afterSignoffAttributedString: NSAttributedString {
        get {
            guard let data = afterSignoffAttributedStringData,
                  let attr = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data) else { return NSAttributedString() }
            return attr
        }
        set {
            afterSignoffAttributedStringData = try? NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: false)
        }
    }

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
    /// Cynical=3.
    public static let defaultBucketShortcutsJSON: String = {
        let pairs = [
            ("standard", "1"), ("professional", "2"), ("unhinged", "3"),
        ]
        let encoded = pairs.map { "{\"bucketId\":\"\($0.0)\",\"digitKey\":\"\($0.1)\",\"modifier\":\"ctrlOpt\"}" }.joined(separator: ",")
        return "[\(encoded)]"
    }()
}
