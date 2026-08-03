import Foundation
import TipKit

// MARK: - Tip Definitions

/// Tip shown when the menu bar is opened and no bucket is selected yet.
/// Encourages the user to pick a bucket before generating.
public struct SelectBucketTip: Tip {
    public static let selectBucketTip = SelectBucketTip()

    public var title: Text {
        Text("Pick a bucket first")
    }

    public var message: Text? {
        Text("Choose a voice — Normal, Professional, Cynical, or Custom — then press Generate.")
    }

    public var image: Image? {
        Image(systemName: "list.bullet.rectangle")
    }

    public var actions: [Action] {
        [
            Action(id: "openSettings", title: "Open Settings → Buckets", perform: {})
        ]
    }

    public var rules: [Rule] {
        #Rule(Self.$hasSeenMenu) { $0 >= 1 }
    }

    @Parameter
    static var hasSeenMenu: Int = 0
}

/// Tip shown when user clicks Generate but hasn't selected a bucket.
public struct GenerateNeedsBucketTip: Tip {
    public static let generateNeedsBucketTip = GenerateNeedsBucketTip()

    public var title: Text {
        Text("Select a bucket to generate")
    }

    public var message: Text? {
        Text("Press a bucket row, then press Generate — or use ⌃⌘1–4 from anywhere.")
    }

    public var image: Image? {
        Image(systemName: "signature")
    }

    public var rules: [Rule] {
        #Rule(Self.$generateAttempted) { $0 == true }
        #Rule(Self.$hasShownTip) { $0 == false }
    }

    @Parameter
    static var generateAttempted: Bool = false

    @Parameter
    static var hasShownTip: Bool = false

    public mutating func didShow() {
        Self.hasShownTip = true
    }
}

/// Tip shown after the first successful generation.
/// Introduces the copy/paste workflow.
public struct FirstGenerationTip: Tip {
    public static let firstGenerationTip = FirstGenerationTip()

    public var title: Text {
        Text("Your signoff is ready")
    }

    public var message: Text? {
        Text("Press Copy to put it on the clipboard, then ⌘V to paste. Or press ⌃⌘C to copy the last one from anywhere.")
    }

    public var image: Image? {
        Image(systemName: "doc.on.doc")
    }

    public var rules: [Rule] {
        #Rule(Self.$hasGeneratedOnce) { $0 == true }
    }

    @Parameter
    static var hasGeneratedOnce: Bool = false
}

/// Tip shown after a few generations — teaches the voice profile in Settings.
public struct TeachVoiceTip: Tip {
    public static let teachVoiceTip = TeachVoiceTip()

    public var title: Text {
        Text("Teach Signoff your voice")
    }

    public var message: Text? {
        Text("Open Settings → Profile and add a self-description. Signoff will write signoffs that sound like you — still on-device.")
    }

    public var image: Image? {
        Image(systemName: "person.text.rectangle")
    }

    public var rules: [Rule] {
        #Rule(Self.$generationCount) { $0 >= 3 }
        #Rule(Self.$hasVoiceDescription) { $0 == false }
    }

    @Parameter
    static var generationCount: Int = 0

    @Parameter
    static var hasVoiceDescription: Bool = false
}

/// Tip for Accessibility permission — appears when auto-paste would fail.
public struct AccessibilityPermissionTip: Tip {
    public static let accessibilityPermissionTip = AccessibilityPermissionTip()

    public var title: Text {
        Text("Grant Accessibility to auto-paste")
    }

    public var message: Text? {
        Text("Signoff needs Accessibility permission to paste directly at your cursor. The menu bar Generate button and shortcuts will still copy to clipboard either way.")
    }

    public var image: Image? {
        Image(systemName: "cursorarrow")
    }

    public var rules: [Rule] {
        #Rule(Self.$autoPasteAttempted) { $0 == true }
        #Rule(Self.$accessibilityGranted) { $0 == false }
    }

    @Parameter
    static var autoPasteAttempted: Bool = false

    @Parameter
    static var accessibilityGranted: Bool = false
}

/// Tip for Input Monitoring permission — appears when global shortcuts don't work.
public struct InputMonitoringPermissionTip: Tip {
    public static let inputMonitoringPermissionTip = InputMonitoringPermissionTip()

    public var title: Text {
        Text("Grant Input Monitoring for global shortcuts")
    }

    public var message: Text? {
        Text("Signoff needs Input Monitoring to listen for ⌃⌘1–4 from any app. You'll still be able to generate from the menu bar and Settings.")
    }

    public var image: Image? {
        Image(systemName: "keyboard")
    }

    public var rules: [Rule] {
        #Rule(Self.$shortcutTriggered) { $0 == true }
        #Rule(Self.$inputMonitoringGranted) { $0 == false }
    }

    @Parameter
    static var shortcutTriggered: Bool = false

    @Parameter
    static var inputMonitoringGranted: Bool = false
}

/// Tip shown when the menu bar icon is hidden (showsStatusItem = false).
public struct HiddenMenuBarTip: Tip {
    public static let hiddenMenuBarTip = HiddenMenuBarTip()

    public var title: Text {
        Text("Menu bar icon is hidden")
    }

    public var message: Text? {
        Text("Signoff still runs in the background — shortcuts and ⌘, (Settings) keep working. Show the icon in Settings → General if you want quick access.")
    }

    public var image: Image? {
        Image(systemName: "eye.slash")
    }

    public var rules: [Rule] {
        #Rule(Self.$isHidden) { $0 == true }
    }

    @Parameter
    static var isHidden: Bool = false
}

/// Tip for the Custom bucket — shown when Custom bucket is enabled but empty.
public struct CustomBucketTip: Tip {
    public static let customBucketTip = CustomBucketTip()

    public var title: Text {
        Text("Custom bucket needs your instructions")
    }

    public var message: Text? {
        Text("Open Settings → Buckets → Custom to write your own rich-text footer — formatting and an image included. Then press ⌃⌘4 to copy or paste it.")
    }

    public var image: Image? {
        Image(systemName: "slider.horizontal.3")
    }

    public var rules: [Rule] {
        #Rule(Self.$customEnabled) { $0 == true }
        #Rule(Self.$customHasInstructions) { $0 == false }
    }

    @Parameter
    static var customEnabled: Bool = false

    @Parameter
    static var customHasInstructions: Bool = false
}

// MARK: - Tip Configuration

/// Configures TipKit for the app. Call once at app launch.
@MainActor
public func configureTips() {
    do {
        try Tips.configure([
            .datastoreLocation(.applicationDefault),
            .displayFrequency(.immediate)
        ])
    } catch {
        NSLog("⚠️ TipKit configure failed: %@", String(describing: error))
    }
}

// MARK: - Tip State Helpers

/// Synchronizes TipKit parameters with AppState values.
/// Call from AppState after initialize() or when relevant state changes.
@MainActor
public func syncTipParameters(appState: AppState) {
    // SelectBucketTip
    SelectBucketTip.hasSeenMenu = appState.hasOpenedMenuBar ? 1 : 0

    // GenerateNeedsBucketTip
    GenerateNeedsBucketTip.generateAttempted = appState.generateAttemptedNoBucket
    GenerateNeedsBucketTip.hasShownTip = appState.generateNeedsBucketTipShown

    // FirstGenerationTip
    FirstGenerationTip.hasGeneratedOnce = appState.hasGeneratedAtLeastOnce

    // TeachVoiceTip
    TeachVoiceTip.generationCount = appState.generationCount
    TeachVoiceTip.hasVoiceDescription = !appState.profile.selfDescription.isEmpty

    // AccessibilityPermissionTip
    AccessibilityPermissionTip.autoPasteAttempted = appState.autoPasteAttempted
    AccessibilityPermissionTip.accessibilityGranted = appState.accessibilityGranted

    // InputMonitoringPermissionTip
    InputMonitoringPermissionTip.shortcutTriggered = appState.hasAttemptedShortcut
    InputMonitoringPermissionTip.inputMonitoringGranted = appState.inputMonitoringGranted

    // HiddenMenuBarTip
    HiddenMenuBarTip.isHidden = !appState.settings.showsStatusItem

    // CustomBucketTip
    if let customBucket = appState.buckets.first(where: { $0.id == BucketID.custom.rawValue }) {
        CustomBucketTip.customEnabled = customBucket.isEnabled
        CustomBucketTip.customHasInstructions = !RichTextFooter.isEmpty(customBucket.footerRTFData)
    }
}