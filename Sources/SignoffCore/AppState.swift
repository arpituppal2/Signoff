import Foundation
import SwiftData
import SwiftUI
import Combine
import Carbon
import AppKit
import TipKit

@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()

    public let persistence = PersistenceController.shared
    public let generation = GenerationService.shared
    public let shortcuts = ShortcutManager.shared
    public let paste = PasteAutomation.shared

    /// Whether Input Monitoring is functional — used by the popover to gate
    /// shortcut indicators. Backed by the REAL Carbon tap install result rather
    /// than `CGPreflightListenEventAccess()` (which reports false on some Macs
    /// even when permission is already granted), so it never nags a working setup.
    @Published public private(set) var inputMonitoringGranted: Bool = false

    /// Whether Accessibility is granted.
    public var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// SwiftUI preview factory. Builds a transient in-memory `AppState` so
    /// `#Preview { ... }` views can render without booting the real store.
    @MainActor public static let preview: AppState = {
        let s = AppState(allowPreviewBootstrap: ())
        return s
    }()

    @Published public var settings: AppSettings = AppSettings()
    @Published public var profile: UserProfile = UserProfile.makeEmpty()
    @Published public var buckets: [Bucket] = []
    @Published public var selectedBucketId: String = BucketID.standard.rawValue
    @Published public var recentGenerations: [SignoffGeneration] = []

    @Published public var generatedText: String?
    @Published public var isGenerating: Bool = false
    /// Last successful generation provider (on-device / bundled) for the popover badge.
    @Published public var lastProviderKind: GenerationProviderKind?
    /// Quiet FM timeout / fallback notice mirrored from `GenerationService.lastStatus`.
    @Published public var lastStatus: GenerationStatusNotice?
    /// End-to-end generate latency (ms). Surfaced in DEBUG popover status only.
    @Published public var lastLatencyMs: Int?
    /// Driven only from `settings.hasCompletedOnboarding` after `initialize()`
    /// (and from Settings "Re-run Onboarding"). Defaults to `false` so a failed
    /// or incomplete launch never leaves the flag stuck "on forever."
    @Published public var showOnboarding: Bool = false
    @Published public var showQuickStart: Bool = false
    /// Set when SwiftData opened via corrupt-store reset or in-memory fallback.
    /// Cleared when the user dismisses the popover recovery card.
    @Published public var storeRecovery: StoreRecovery?

    // MARK: - TipKit state

    /// Has the user ever opened the menu bar?
    @Published public var hasOpenedMenuBar: Bool = false
    /// Did the user attempt Generate with no bucket selected?
    @Published public var generateAttemptedNoBucket: Bool = false
    /// Has the "Generate needs bucket" tip been shown?
    @Published public var generateNeedsBucketTipShown: Bool = false
    /// Has at least one generation succeeded?
    @Published public var hasGeneratedAtLeastOnce: Bool = false
    /// Total successful generations (for TeachVoiceTip threshold)
    @Published public var generationCount: Int = 0
    /// Did user attempt auto-paste (menu bar Generate with shouldAutoPaste)?
    @Published public var autoPasteAttempted: Bool = false
    /// Has user triggered a global shortcut?
    @Published public var hasAttemptedShortcut: Bool = false

    public var selectedBucket: Bucket? {
        buckets.first { $0.id == selectedBucketId }
    }

    private var cancellables = Set<AnyCancellable>()
    /// Guards one-shot cold-start work so `bootstrap()` / `initialize()` are
    /// idempotent for AppIntents and app launch.
    private var didInitialize = false

    /// Internal designated initializer. The public path is `.shared`; SwiftUI
    /// previews use the `preview` static factory which calls this directly with
    /// a sentinel argument so we don't double-init the real store.
    init(allowPreviewBootstrap _: Void) {
        // No-op: SwiftUI previews don't need the persistence/shortcut pipeline.
    }

    private init() {}
    
    /// Fire haptic feedback for clipboard actions (HIG: feedback § — use sound and haptics to enhance feedback).
    private func fireClipboardHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    /// TASK-13 (PF-bundle): cold-start binding for AppIntents and other
    /// cross-actor callers. Ensures persistence, buckets, history, and the
    /// generation->persistence attach are ready before `@Published` mutation.
    /// Idempotent; safe to call repeatedly (forwards to `initialize()`).
    @MainActor
    public func bootstrap() async throws {
        try await initialize()
    }

    public func initialize() async throws {
        guard !didInitialize else { return }

        // GenerationService only commits history when persistence is attached;
        // without this, `recordGeneration` never runs and recentGenerations
        // stays frozen at the init-time snapshot.
        generation.attach(persistence: persistence)

        try persistence.initializeDefaultsIfNeeded()
        settings = try persistence.fetchSettings()
        profile = try persistence.fetchProfile() ?? UserProfile.makeEmpty()
        buckets = try persistence.fetchEnabledBuckets()
        if buckets.isEmpty { buckets = Bucket.defaultBuckets() }
        if !buckets.contains(where: { $0.id == selectedBucketId }) {
            selectedBucketId = buckets.first?.id ?? BucketID.standard.rawValue
        }
        refreshRecentGenerations()
        syncOnboardingFlagFromSettings()
        // v3: drop history older than 3 days (favorites kept) on each launch.
        try? persistence.pruneGenerations(olderThanDays: 3)
        // Soft-fail surface: corrupt / unreadable store must not crash launch;
        // show a one-shot recovery card in the popover instead.
        storeRecovery = persistence.storeRecovery
        if persistence.recoveredFromStoreFailure {
            Task { await SystemSoundClient.shared.play(.blow) }
        }

        // Wire shortcut hub — block-based observers hop onto the main actor;
        // @objc selectors would run on the CarbonEventTap thread and race
        // against @Published mutations under StrictConcurrency.
        NotificationCenter.default.publisher(for: .shortcutTapFailed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                MainActor.assumeIsolated {
                    guard let failure = note.object as? CarbonEventTap.TapFailure else { return }
                    self?.handleShortcutTapFailure(failure)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: Notification.Name("com.signoff.copyLast"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.copyMostRecent()
                }
            }
            .store(in: &cancellables)
        // Keep the popover's permission indicator in sync with the REAL tap
        // install state (drives @Published inputMonitoringGranted).
        shortcuts.$isTapFunctional
            .receive(on: DispatchQueue.main)
            .sink { [weak self] functional in
                MainActor.assumeIsolated {
                    self?.inputMonitoringGranted = functional
                }
            }
            .store(in: &cancellables)
        await registerShortcutBindings()
        
        // Warm the per-bucket phrase cache from Apple Foundation Models in the
        // background. The cache starts empty and is filled *only* by the
        // on-device model — there is no static phrasebook seed — so the model
        // actually runs and its cost is real.
        BucketCache.shared.warmup(buckets: buckets,
                                  profile: UserProfileSnapshot(profile: profile),
                                  ageGroup: settings.generationAgeGroup)

        await generation.warmup()

        // Initialize VoiceProfile after persistence is ready
        try? persistence.initializeVoiceProfile()
        VoiceProfile.initialize()

        // Start SilentLearningEngine if Accessibility is granted
        if accessibilityGranted {
            await SilentLearningEngine.shared.start()
        }

        // Sync TipKit parameters after initialization
        syncTipParameters(appState: self)

        didInitialize = true
    }

    /// Re-read the newest generations from SwiftData into `@Published` state.
    @MainActor
    public func refreshRecentGenerations(limit: Int = 50) {
        recentGenerations = (try? persistence.fetchGenerations(limit: limit)) ?? recentGenerations
    }

    /// v3: delete a generation from history (trash button).
    @MainActor
    public func deleteGeneration(_ generation: SignoffGeneration) {
        try? persistence.deleteGeneration(generation)
        refreshRecentGenerations()
    }

    /// v3: thumbs up / thumbs down explicit feedback on a history entry.
    @MainActor
    public func applyFeedback(_ generation: SignoffGeneration, liked: Bool) {
        try? persistence.applyFeedback(generation, liked: liked)
        refreshRecentGenerations()
    }

    @MainActor
    private func handleShortcutTapFailure(_ failure: CarbonEventTap.TapFailure) {
        // Tap-install failures are surfaced PASSIVELY: `inputMonitoringGranted`
        // (drives the TipKit indicator) and `boundShortcutConflicts` (drives the
        // Settings → Shortcuts conflict banner). We deliberately do NOT hijack
        // `generatedText` here — `generatedText` is for generation results, and
        // clobbering it with a permission nag on every launch (the tap is
        // (re)installed at launch and whenever bindings change) is the wrong
        // affordance. With ad-hoc signing the bundle signature changes each build,
        // so `CGEvent.tapCreate` can return nil even when System Settings shows
        // Input Monitoring toggled on; a launch-time nag cannot fix that and only
        // annoys. The Shortcuts Settings pane is where the user resolves it.
        switch failure {
        case .eventTapDenied, .runLoopSourceCreateFailed, .tapEnableFailed:
            break
        }
    }

    /// Pause / resume global Carbon shortcuts (Command Menu toggle).
    @MainActor
    public func setShortcutsPaused(_ paused: Bool) {
        shortcuts.isPaused = paused
        if paused {
            shortcuts.stop()
        } else {
            Task { await registerShortcutBindings() }
        }
    }

    /// Persist bindings, re-probe, and re-register the Carbon tap.
    @MainActor
    public func applyShortcutBindings(_ bindings: [ShortcutManager.BucketBinding]) async {
        settings.bucketShortcutsJSON = shortcuts.encode(bindings)
        settings.updatedAt = Date()
        try? persistence.context.save()
        await registerShortcutBindings()
    }

    /// One-tap Mission Control escape hatch — switch every bucket to ⌥⌘N.
    @MainActor
    public func switchAllShortcutsToOptCmd() async {
        await applyShortcutBindings(shortcuts.optCmdDefaults())
    }

    /// Start the silent learning engine when Accessibility is granted.
    /// Called from onboarding when user grants Accessibility permission.
    @MainActor
    public func startLearningEngineIfNeeded() async {
        guard accessibilityGranted else { return }
        await SilentLearningEngine.shared.start()
    }

    /// Public so `SignoffMenuContent` (SignoffUI target) can wire its Copy-last
    /// button.
    @MainActor
    public func copyMostRecent() {
        guard let last = recentGenerations.first else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(last.text, forType: .string)
    }

    /// Dismiss the quiet FM timeout / fallback status line.
    @MainActor
    public func dismissGenerationStatus() {
        lastStatus = nil
        generation.clearStatus()
    }

    /// Keeps `showOnboarding` in lockstep with the persisted settings row.
    ///
    /// Existing installs that finished an older onboarding re-see it once when
    /// `requiredOnboardingVersion` is bumped (e.g. when we add the age question),
    /// because `onboardingVersionSeen` lags behind. New installs always see it
    /// (`hasCompletedOnboarding == false`).
    @MainActor
    public func syncOnboardingFlagFromSettings() {
        let completed = settings.hasCompletedOnboarding
        let seenVersion = settings.onboardingVersionSeen ?? 0
        let needsRefresh = seenVersion < Self.requiredOnboardingVersion
        showOnboarding = !completed || needsRefresh
    }

    /// Bump this when the onboarding materially changes (new step, new
    /// required field) and every existing user should see it once more.
    /// v2 adds the age-group question that drives on-device voice.
    public static let requiredOnboardingVersion: Int = 2

    /// Persist completion of the first-run setup panel (and clear the live
    /// flag). Stamps the current required onboarding version so a future bump
    /// is the only thing that re-triggers it.
    @MainActor
    public func markOnboardingCompleted() {
        settings.hasCompletedOnboarding = true
        settings.onboardingVersionSeen = Self.requiredOnboardingVersion
        settings.updatedAt = Date()
        showOnboarding = false
        try? persistence.context.save()
    }

    /// Settings / Help "Re-run Onboarding" — clear the gate so the setup panel can reopen.
    @MainActor
    public func resetOnboardingForReplay() {
        settings.hasCompletedOnboarding = false
        settings.updatedAt = Date()
        showOnboarding = true
        try? persistence.context.save()
    }

    public func registerShortcutBindings() async {
        if shortcuts.isPaused {
            shortcuts.stop()
            return
        }
        let bindings = shortcuts.decode(settings.bucketShortcutsJSON)
        _ = await shortcuts.probe(bindings: bindings)
        await shortcuts.register(bindings: bindings) { [weak self] bucketId in
            Task { @MainActor in
                guard let self, !self.shortcuts.isPaused else { return }
                self.selectedBucketId = bucketId
                await self.generateNow()
            }
        }
    }

    /// Generate a signoff and optionally auto-paste at the cursor.
    /// - Parameter shouldAutoPaste: When `true` (popover button), writes to
    ///   clipboard + synthesizes ⌘V at cursor. When `false` (shortcut,
    ///   intent, menu), only copies to clipboard — user presses ⌘V to paste
    ///   manually. Default `false` to prevent surprise pastes from global
    ///   keyboard shortcuts.
    public func generateNow(shouldAutoPaste: Bool = false) async {
        NotificationCenter.default.post(name: .signoffMenuBarAppUsed, object: nil)
        // Track if user attempted generate with no bucket selected
        if selectedBucket == nil {
            generateAttemptedNoBucket = true
            return
        }
        guard !isGenerating, let bucket = selectedBucket else { return }
        isGenerating = true
        defer { isGenerating = false }
        generatedText = nil
        lastStatus = nil
        generation.clearStatus()

        // Track auto-paste attempt for AccessibilityPermissionTip
        if shouldAutoPaste {
            autoPasteAttempted = true
        }

        // Custom bucket: no model involved — the user's rich-text footer *is*
        // the signoff. Copy as RTF (+ image), optionally paste at the cursor.
        if bucket.id == BucketID.custom.rawValue {
            await generateCustomFooter(bucket: bucket, shouldAutoPaste: shouldAutoPaste)
            return
        }

        let outcome = await generation.generate(
            bucketId: bucket.id,
            profile: profile,
            recentTexts: recentGenerations.map(\.text),
            unhingedLevel: bucket.unhingedLevel,
            toneValue: bucket.toneValue,
            postfixMode: bucket.postfixMode,
            customInstructions: bucket.customInstructions,
            phraseList: bucket.phraseListJSON,
            ageGroup: settings.generationAgeGroup,
            nsfwEnabled: bucket.nsfwEnabled
        )
        switch outcome {
        case .success(let o):
            generatedText = o.text
            lastProviderKind = o.providerKind
            lastLatencyMs = o.latencyMs
            lastStatus = nil

            // Track successful generation for tips
            hasGeneratedAtLeastOnce = true
            generationCount += 1

        case .providerFailed:
            generatedText = nil
            lastProviderKind = nil
            lastLatencyMs = nil
            lastStatus = nil
        case .usageLimitReached:
            // No longer enforced — Signoff is free. Treat as provider failure.
            generatedText = nil
            lastProviderKind = nil
            lastLatencyMs = nil
            lastStatus = nil
        }

        guard let txt = generatedText else { return }

        // Always copy to clipboard so the text is ready for ⌘V
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(txt, forType: .string)

        // Auto-paste only when explicitly requested (popover Generate button)
        if shouldAutoPaste {
            _ = await commitGeneratedPaste(txt)
        } else {
            // HIG feedback §: use sound and haptics to enhance feedback
            fireClipboardHaptic()
        }
    }

    /// CTA copy when ⌘V synthesis fails because Accessibility is denied.
    public static let accessibilityDeniedCTA =
        "⌘V didn't land — grant Accessibility in System Settings → Privacy & Security → Accessibility and retry."

    /// Custom bucket: copy the user-authored rich-text footer (RTF + image) to
    /// the clipboard, optionally paste it at the cursor. No model is called.
    private func generateCustomFooter(bucket: Bucket, shouldAutoPaste: Bool) async {
        let footerData = bucket.footerRTFData
        guard let footer = RichTextFooter.attributed(from: footerData),
              !footer.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            generatedText = "Write a footer under Settings → Buckets → Custom first, then generate."
            lastProviderKind = nil
            lastLatencyMs = nil
            lastStatus = nil
            return
        }

        let plain = footer.string
        generatedText = plain
        lastProviderKind = nil
        lastLatencyMs = 0
        lastStatus = nil
        hasGeneratedAtLeastOnce = true
        generationCount += 1

        // Record in history so Recent / Copy Last keep working like other buckets.
        await PersistenceController.shared.recordGeneration(
            bucketId: bucket.id, text: plain, providerRaw: "custom-footer", latencyMs: 0)

        guard RichTextFooter.writeRTF(footer, to: NSPasteboard.general) else {
            generatedText = "Clipboard write failed — pasteboard may be locked."
            return
        }

        if shouldAutoPaste {
            _ = await commitGeneratedPaste(attributed: footer)
        } else {
            fireClipboardHaptic()
        }
    }

    /// Attempts paste and maps `PasteError onto `generatedText` + a single audio cue.
    @discardableResult
    func commitGeneratedPaste(_ text: String) async -> Bool {
        var pasteSucceeded = false
        do {
            try await paste.paste(text)
            pasteSucceeded = true
        } catch PasteError.accessibilityDenied {
            generatedText = Self.accessibilityDeniedCTA
        } catch PasteError.pasteboardWriteFailed {
            generatedText = "Clipboard write failed — pasteboard may be locked."
        } catch {
            generatedText = "Paste failed (unexpected)."
        }
        if pasteSucceeded {
            await SystemSoundClient.shared.play(.tink)
        } else {
            await SystemSoundClient.shared.play(.basso)
        }
        return pasteSucceeded
    }

    /// Attributed variant used by the Custom bucket — the rich footer is already
    /// on the pasteboard, so the paste just synthesizes ⌘V against it.
    @discardableResult
    func commitGeneratedPaste(attributed footer: NSAttributedString) async -> Bool {
        var pasteSucceeded = false
        do {
            try await paste.paste(footer)
            pasteSucceeded = true
        } catch PasteError.accessibilityDenied {
            generatedText = Self.accessibilityDeniedCTA
        } catch PasteError.pasteboardWriteFailed {
            generatedText = "Clipboard write failed — pasteboard may be locked."
        } catch {
            generatedText = "Paste failed (unexpected)."
        }
        if pasteSucceeded {
            await SystemSoundClient.shared.play(.tink)
        } else {
            await SystemSoundClient.shared.play(.basso)
        }
        return pasteSucceeded
    }
}

// MARK: - Cross-target notification extensions

public extension Notification.Name {
    static let signoffNeedsA11yExplainer =
        Notification.Name("signoff.needsA11yExplainer")
    static let signoffCheckForUpdates =
        Notification.Name("signoff.checkForUpdates")
    static let signoffShowWhatsNew =
        Notification.Name("signoff.showWhatsNew")
    static let signoffShowsStatusItemDidChange =
        Notification.Name("signoff.showsStatusItemDidChange")
    static let openSettingsShortcutTriggered =
        Notification.Name("signoff.openSettingsShortcutTriggered")
    static let toggleMenuBarPopover =
        Notification.Name("signoff.toggleMenuBarPopover")
    static let shortcutTapFailed =
        Notification.Name("signoff.shortcutTapFailed")
    static let signoffMenuBarAppUsed =
        Notification.Name("signoff.menuBarAppUsed")
}
