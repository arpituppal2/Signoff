import Foundation
import SwiftData
import SwiftUI
import Combine
import Carbon
import AppKit
import os.log

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

    /// Has the user ever opened the menu bar?
    @Published public var hasOpenedMenuBar: Bool = false
    /// Did the user attempt Generate with no bucket selected?
    @Published public var generateAttemptedNoBucket: Bool = false
    /// Prevents re-posting the first-open notification.
    private var hasPostedFirstOpen: Bool = false

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

    public var selectedBucket: Bucket? {
        buckets.first { $0.id == selectedBucketId }
    }

    private var cancellables = Set<AnyCancellable>()
    /// Guards one-shot cold-start work so `bootstrap()` / `initialize()` are
    /// idempotent for AppIntents and app launch.
    private var didInitialize = false

    /// The CTA string shown in `generatedText` when Accessibility is denied.
    /// This is a single source of truth for the message so tests and UI stay in sync.
    public static let accessibilityDeniedCTA = "⌘V failed — grant Accessibility in System Settings → Privacy & Security, then retry."

    /// Preview-only instance for SwiftUI previews and unit tests.
    /// Uses the preview initializer that skips the real pipeline.
    public static let preview: AppState = AppState()

    /// Private designated initializer. The public path is `.shared`; SwiftUI
    /// previews use the `preview` static property which calls this with a
    /// sentinel argument so we don't double-init the real store.
    private init(_: Void = ()) {
    }

    /// Fire haptic feedback for clipboard actions (HIG: feedback § — use sound and haptics to enhance feedback).
    private func fireClipboardHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    /// Retry shortcut registration if the Carbon tap isn't functional (e.g. after
    /// Input Monitoring permission is granted). Called when app becomes active.
    @MainActor
    private func retryShortcutRegistrationIfNeeded() {
        guard !shortcuts.isTapFunctional, !shortcuts.isPaused else { return }
        Task { await registerShortcutBindings() }
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
        // Migration: ensure shortcut bindings use ctrlOpt (⌃⌥) not optCmd (⌥⌘)
        let currentBindings = shortcuts.decode(settings.bucketShortcutsJSON)
        let needsMigration = currentBindings.contains { $0.modifier == "optCmd" }
        if needsMigration {
            let newBindings = shortcuts.ctrlOptDefaults()
            settings.bucketShortcutsJSON = shortcuts.encode(newBindings)
            settings.updatedAt = Date()
            try? persistence.context.save()
        }
        profile = try persistence.fetchProfile() ?? UserProfile.makeEmpty()
        buckets = try persistence.fetchEnabledBuckets()
        if buckets.isEmpty { buckets = Bucket.defaultBuckets() }

        // Normalize bucket configs to prevent stale SwiftData overrides:
        // - standard (Normal): never has unhingedLevel
        // - professional: never has unhingedLevel (uses toneValue instead)
        // - unhinged (Cynical): unhingedLevel = .cynical
        for bucket in buckets {
            var needsSave = false
            switch bucket.id {
            case BucketID.standard.rawValue:
                if bucket.unhingedLevel != nil {
                    bucket.unhingedLevel = nil
                    needsSave = true
                }
            case BucketID.professional.rawValue:
                if bucket.unhingedLevel != nil {
                    bucket.unhingedLevel = nil
                    needsSave = true
                }
            case BucketID.unhinged.rawValue:
                if bucket.unhingedLevel != .cynical {
                    bucket.unhingedLevel = .cynical
                    needsSave = true
                }
            default:
                break
            }
            if needsSave {
                bucket.updatedAt = Date()
            }
        }

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

        // Proactively prompt for Input Monitoring if not granted.
        // This ensures the system dialog appears on first launch without waiting
        // for the Carbon tap to fail (which happens asynchronously).
        if !InputMonitoringAccess.isGranted() {
            Task { @MainActor in
                InputMonitoringAccess.request()
            }
        }

        // Warm the per-bucket phrase cache from Apple Foundation Models in the
        // background. The cache starts empty and is filled *only* by the
        // on-device model — there is no static phrasebook seed — so the model
        // actually runs and its cost is real.
        // DISABLED: BucketCache.shared.clearAll()
        // BucketCache.shared.warmup(buckets: buckets,
        //                        profile: UserProfileSnapshot(profile: profile),
        //                        ageGroup: settings.generationAgeGroup)

        // DISABLED: warmup/prewarm seems to corrupt content filter state
        // await generation.warmup()

        // Observe first menu bar open to trigger splash
        $hasOpenedMenuBar
            .filter { $0 }
            .first()
            .sink { [weak self] _ in
                guard let self, !self.hasPostedFirstOpen else { return }
                self.hasPostedFirstOpen = true
                NotificationCenter.default.post(name: .signoffMenuBarFirstOpen, object: nil)
            }
            .store(in: &cancellables)

        // Retry shortcut registration when app becomes active (e.g. after user
        // grants Input Monitoring permission in System Settings).
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.retryShortcutRegistrationIfNeeded()
                }
            }
            .store(in: &cancellables)

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

    /// One-tap Mission Control escape hatch — switch every bucket to ⌃⌥N.
    @MainActor
    public func switchAllShortcutsToCtrlOpt() async {
        await applyShortcutBindings(shortcuts.ctrlOptDefaults())
    }

    /// Switch every bucket shortcut to ⌥⌘N (Option-Command digits).
    @MainActor
    public func switchAllShortcutsToOptCmd() async {
        await applyShortcutBindings(shortcuts.optCmdDefaults())
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
        let specialBindings = decodeSpecialBindings()
        await shortcuts.register(
            bindings: bindings,
            specialBindings: specialBindings
        ) { [weak self] bucketId in
            Task { @MainActor in
                guard let self, !self.shortcuts.isPaused else { return }
                self.selectedBucketId = bucketId
                // Fire the at-caret signature animation *before* generation so
                // the user sees feedback exactly where they're typing; it fades
                // out by the time the paste lands. Resolved & shown by the app
                // delegate (SignoffUI overlay + SignoffCore caret locator).
                NotificationCenter.default.post(name: .signoffShortcutGenerateStarted, object: nil)
                // Shortcut auto-paste respects the user's settings toggle.
                await self.generateNow(shouldAutoPaste: self.settings.shortcutAutoPaste)
            }
        } runSpecialAction: { [weak self] action in
            Task { @MainActor in
                guard let self, !self.shortcuts.isPaused else { return }
                switch action {
                case .pasteAfterSignoff:
                    await self.pasteAfterSignoffOnly()
                }
            }
        }
    }

    /// Decode the persisted JSON of special-action bindings; fall back to the
    /// default ⌃⌥F chord so the feature works out of the box.
    private func decodeSpecialBindings() -> [ShortcutManager.SpecialActionBinding] {
        let raw = settings.afterSignoffShortcutJSON
        if !raw.isEmpty,
           let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([ShortcutManager.SpecialActionBinding].self, from: data),
           !decoded.isEmpty {
            return decoded
        }
        return [ShortcutManager.SpecialActionBinding(action: .pasteAfterSignoff, digitKey: "f", modifier: "ctrlOpt")]
    }

    /// Paste just the "After Signoff" footer content — no generated signoff.
    /// Uses rich text if present, else plain text from the configured footer.
    public func pasteAfterSignoffOnly() async {
        let attr = settings.afterSignoffAttributedString
        let trimmed = attr.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            NSSound.beep()
            return
        }
        NotificationCenter.default.post(name: .signoffShortcutGenerateStarted, object: nil)
        do {
            if attr.length > 0 && attr.attribute(.attachment, at: 0, effectiveRange: nil) != nil {
                try await paste.paste(attr)
            } else {
                try await paste.paste(trimmed)
            }
            await SystemSoundClient.shared.play(.tink)
        } catch PasteError.accessibilityDenied {
            generatedText = Self.accessibilityDeniedCTA
        } catch PasteError.pasteboardWriteFailed {
            generatedText = "Clipboard write failed — pasteboard may be locked."
        } catch {
            generatedText = "Paste failed (unexpected)."
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
            generatedText = applyAfterSignoff(to: o.text)
            lastProviderKind = o.providerKind
            lastLatencyMs = o.latencyMs
            lastStatus = nil

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

    /// Attempts paste and maps `PasteError` onto `generatedText` + a single audio cue.
    /// When rapid-replace is enabled and the trigger lands within the cooldown
    /// window after the last paste, the previously-pasted text is selected and
    /// pasted over instead of appending at the cursor.
    @discardableResult
    func commitGeneratedPaste(_ text: String) async -> Bool {
        var pasteSucceeded = false
        do {
            if shouldRapidReplace() {
                try await paste.replacePreviousAndPaste(text)
            } else {
                try await paste.paste(text)
            }
            pasteSucceeded = true
        } catch PasteError.accessibilityDenied {
            // Keep generatedText visible so user can manually copy.
            // The PasteAutomation layer will trigger the system Accessibility prompt.
            generatedText = Self.accessibilityDeniedCTA
            pasteSucceeded = false
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

    /// Append the user's configured "after signoff" text below the generated
    /// signoff in the format: [signoff],\n[afterText]. If empty, returns the
    /// signoff unchanged. Supports rich text (multi-line, images).
    private func applyAfterSignoff(to text: String) -> String {
        let attr = settings.afterSignoffAttributedString
        let trimmed = attr.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        return "\(text)\n\(trimmed)"
    }

    /// True when rapid-replace is enabled AND this trigger falls inside the
    /// cooldown window after the last paste. The prior paste is forgotten once
    /// the window expires so the next paste inserts normally.
    private func shouldRapidReplace() -> Bool {
        guard settings.rapidReplaceEnabled,
              let lastAt = paste.lastPastedAt,
              let lastText = paste.lastPastedText, !lastText.isEmpty else {
            return false
        }
        let elapsed = Date().timeIntervalSince(lastAt)
        let cooldown = Double(settings.rapidReplaceCooldownSeconds)
        if elapsed <= cooldown {
            return true
        } else {
            // Window expired — forget so a later trigger pastes fresh.
            paste.forgetLastPaste()
            return false
        }
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
    static let signoffMenuBarFirstOpen =
        Notification.Name("signoff.menuBarFirstOpen")
    /// Fired to ask the app to present/re-open the onboarding window
    /// (Settings → Advanced → Re-run onboarding). The delegate owns the
    /// `openWindow(id:)` call because SwiftUI scene-opening has to happen
    /// from the App, not from a SwiftData/Core model file.
    static let signoffOnboardingRequested =
        Notification.Name("signoff.onboardingRequested")
    /// Fired the instant a global generate shortcut fires (before generation),
    /// so the UI can show the at-caret signature animation where the user is
    /// typing. The paste lands later, once generation + ⌘V complete.
    static let signoffShortcutGenerateStarted =
        Notification.Name("signoff.shortcutGenerateStarted")
}