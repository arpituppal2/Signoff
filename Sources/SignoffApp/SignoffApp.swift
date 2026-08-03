import SwiftUI
import AppKit
import Combine
import os
import SignoffCore
import SignoffUI

/// Single-source-of-truth app glue. v2 spec §21 ship-locked.
@main
struct SignoffApp: App {
    @NSApplicationDelegateAdaptor(SignoffDelegate.self) var delegate
    /// Bridges `AppState.shared.@Published` flags into the CommandMenu's
    /// `.disabled(...)` closures so the Signoff submenu's "Generate Signoff"
    /// item correctly dims while a generation is in flight, AND so "Copy Last
    /// Signoff" correctly dims when the recent-strip is empty.
    @State private var menuState = SignoffMenuState()

    var body: some Scene {
        // Onboarding — its own window so it's a real, focusable macOS surface
        // (not a sheet dangling off a hidden host). Gated by `showOnboarding`,
        // which `AppState` derives from `settings.hasCompletedOnboarding` +
        // `requiredOnboardingVersion` after `initialize()`.
        WindowGroup("Welcome to Signoff", id: "signoff.onboarding") {
            if AppState.shared.showOnboarding {
                OnboardingView()
                    .environment(AppState.shared)
            } else {
                EmptyView()
            }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 560)

        // History window
        Window("History", id: "signoff.history") {
            HistoryView()
                .environment(AppState.shared)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 560)

        // Hidden settings context — MUST precede the Settings scene so the
        // `openSettings` environment action resolves (macOS 14+ moved Settings
        // opening off the showSettingsWindow: selectors; see SettingsContextView).
        // A live Window scene is required (suppressing it kills the environment
        // action); the 1×1 window is kept invisible by an observer that orders
        // it out the instant it appears (a raw 1×1 Window scene flashed a sliver
        // and could crash release builds with a SwiftUI constraint-pass exception,
        // so `.windowResizability(.contentSize)` must stay off).
        Window("Signoff Settings Context", id: "signoff.settings-context") {
            SettingsContextView()
        }
        .defaultSize(width: 1, height: 1)

        Settings {
            SettingsView()
                .environment(AppState.shared)
        }
        // Menu bar extra. `.window` (popover) is required — SignoffMenuContent is
        // a rich popover surface (ScrollView, toast overlay, custom button styles,
        // page fills) that an NSMenu (`.menu` style) cannot represent; `.menu`
        // silently strips anything that isn't a menu item.
        MenuBarExtra(content: {
            SignoffMenuContent()
                .environment(AppState.shared)
        }, label: {
            // Inject AppState directly on the label view (scene-level
            // .environment does not propagate into the MenuBarExtra label
            // closure the way it does into the content closure). This lets
            // MenuBarLabelView observe `appState.isGenerating` and drive the
            // drawOn signature animation while a generation is in flight.
            MenuBarLabelView()
                .environment(AppState.shared)
        })
        .menuBarExtraStyle(.window)

        .commands {
            CommandMenu("Signoff") {
                Button("Generate Signoff") {
                    Task { await AppState.shared.generateNow() }
                }
                .disabled(menuState.isGenerating)
                Menu("Generate from Bucket") {
                    ForEach(menuState.bucketMenuItems) { item in
                        Button(item.name) {
                            Task {
                                AppState.shared.selectedBucketId = item.id
                                await AppState.shared.generateNow()
                            }
                        }
                        .disabled(menuState.isGenerating || !item.allowed)
                    }
                }
                Button("Copy Last Signoff") {
                    AppState.shared.copyMostRecent()
                }
                .keyboardShortcut("c", modifiers: [.control, .shift])
                .disabled(!menuState.hasRecent)
                Divider()
                Toggle("Pause Shortcuts", isOn: Binding(
                    get: { menuState.shortcutsPaused },
                    set: { AppState.shared.setShortcutsPaused($0) }
                ))
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Signoff") {
                    AboutWindowController.shared.present()
                }
            }
            CommandGroup(after: .appInfo) {
                // Custom ⌘,. Opening the Settings scene directly — the popover
                // auto-dismisses when the Settings window becomes key.
                //
                // DO NOT post .toggleMenuBarPopover first. That routes through
                // MenuBarOpener.toggle() → statusItem.button.performClick(nil):
                // a synthetic click on the popover's own status item, delivered
                // while we're already inside the popover's event-handling. That
                // re-entrant AppKit event delivery deadlocks the main thread
                // (the freeze, not a crash — no .crash log is written). The
                // earlier "close popover first, then open Settings" advice was
                // the bug.
                Button("Settings…") {
                    NotificationCenter.default.post(name: .openSettingsShortcutTriggered, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("Signoff Help") {
                    HelpOverlayWindowController.shared.present()
                }
                .keyboardShortcut("?", modifiers: .command)
                Button("What's New…") {
                    NotificationCenter.default.post(name: .signoffShowWhatsNew, object: nil)
                }
                Button("Check for Updates…") {
                    NotificationCenter.default.post(name: .signoffCheckForUpdates, object: nil)
                }
            }
        }
    }
}

@MainActor
final class SignoffDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState { AppState.shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prefer Info.plist LSUIElement = YES for the shipping bundle.
        // Keep .accessory as a belt-and-suspenders for `swift run` / unsigned
        // SPM launches that may lack the plist key.
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }

        let launchSignpost = SignoffSignpost.coldLaunch.makeSignpostID()
        let launchState = SignoffSignpost.coldLaunch.beginInterval("launch", id: launchSignpost)

        SparkleIntegration.shared.startIfNeeded()

        // No launch-time prewarm — every generation is a live on-device call by
        // user request. Prewarming fired the model for 3 buckets at boot, which
        // read as "generating several at once" and produced canned-looking output.


        Task {
            do {
                try await appState.initialize()
                SignoffSignpost.coldLaunch.endInterval("launch", launchState)
                // Onboarding reveal is driven by `SignoffMenuContent` which
                // observes `showOnboarding` and owns `@Environment(\.openWindow)`.
                // We only flip the flag here; the scene opens the window.
            } catch {
                NSLog("❌ Signoff init failed: %@", String(describing: error))
                SignoffSignpost.coldLaunch.endInterval("launch", launchState)
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(presentA11yExplainer),
                                               name: .signoffNeedsA11yExplainer, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(checkForUpdates),
                                               name: .signoffCheckForUpdates, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showWhatsNew),
                                               name: .signoffShowWhatsNew, object: nil)
        // Input Monitoring alert is driven by the REAL tap install result, not
        // `CGPreflightListenEventAccess()` (which returns false on some Macs even
        // when Input Monitoring is already granted). `.eventTapDenied` is only
        // posted when `CGEvent.tapCreate` actually returns nil. Only shown once
        // per version — repeated launch nags don't fix chord conflicts.
        NotificationCenter.default.addObserver(self, selector: #selector(handleShortcutTapFailure(_:)),
                                               name: .shortcutTapFailed, object: nil)
        // ⌃⌘` opens the menu bar popover from any app.
        NotificationCenter.default.addObserver(self, selector: #selector(openMenuBarPopover),
                                               name: .toggleMenuBarPopover, object: nil)
        // Global generate shortcut → animate a little signature at the caret
        // where the user is typing, before the paste lands.
        NotificationCenter.default.addObserver(self, selector: #selector(showSignatureAtCaret),
                                               name: .signoffShortcutGenerateStarted, object: nil)
        // History + Settings are now opened directly from the popover via
        // @Environment(\.openWindow) / the settings-context bridge — no
        // AppDelegate observer needed (the old sendAction fallback hit a
        // selector no responder implemented).

        // Main-thread watchdog: if the main thread stops responding for ~8s
        // (a SwiftUI render loop / re-entrant AppKit deadlock — the Settings
        // beach-ball class of hang), the app never exits, so the OS never
        // relaunches it and the user is left staring at a frozen menu bar with
        // no way out. This watchdog runs on a BACKGROUND queue and pings the
        // main thread every 2s; if three consecutive pings go unanswered the
        // main thread is hung, and the watchdog force-relaunches the app
        // (terminate + re-open via `open`). It works precisely BECAUSE it
        // doesn't run on the main thread — a hung main thread cannot rescue
        // itself. Disabled in DEBUG via the SIGNOFF_DISABLE_WATCHDOG env var
        // so it never interferes with attaching a debugger to a deliberate
        // main-thread stall during development.
        MainThreadWatchdog.shared.startIfNeeded()
    }

    @objc private func showSignatureAtCaret() {
        MainActor.assumeIsolated {
            var rect = CaretLocator.shared.caretScreenRect()
            // Fallback: animate above the menu bar (top-right) if we can't resolve
            // the caret — still gives feedback, never blocks the paste.
            if rect == nil, let screen = NSScreen.main ?? NSScreen.screens.first {
                let mb = NSStatusBar.system.thickness
                rect = NSRect(x: screen.frame.maxX - 120,
                              y: screen.frame.maxY - mb - 60,
                              width: 80, height: 50)
            }
            SignatureOverlayWindow.shared.show(at: rect, duration: 0.9)
        }
    }

    @objc private func openMenuBarPopover() {
        MenuBarOpener.toggle()
    }

    @objc private func handleShortcutTapFailure(_ notification: Notification) {
        guard let failure = notification.object as? CarbonEventTap.TapFailure else { return }
        if case .eventTapDenied = failure {
            // Ad-hoc signed builds: CGPreflightListenEventAccess() returns false
            // even when the toggle is ON in System Settings because the CDHash
            // changes each build. The tap failure is the real signal — don't nag
            // on stale preflight. If it's a chord conflict, Settings → Shortcuts
            // shows the banner; if it's a permission issue, the user already
            // opened System Settings once (the toggle is ON) so re-launch is
            // needed anyway. Skip the alert entirely.
            return
        }
    }

    // MARK: - Help Handlers

    @objc private func presentA11yExplainer() {
        _ = PasteAutomation.shared.requestPermission()
    }

    @objc private func checkForUpdates() {
        SparkleIntegration.shared.checkForUpdates()
    }

    @objc private func showWhatsNew() {
        SparkleIntegration.shared.showWhatsNew()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Dock-less (LSUIElement): reopen recovers Settings when there
        // are no keyable windows. MenuBarExtra is always visible with .accessory policy.
        if !flag {
            SettingsOpener.open(pane: "General")
        }
        return true
    }
}

@MainActor
@Observable
private final class SignoffMenuState {
    struct BucketMenuItem: Identifiable, Equatable {
        let id: String
        let name: String
        let allowed: Bool
    }

    var isGenerating: Bool = false
    var hasRecent: Bool = false
    var bucketMenuItems: [BucketMenuItem] = []
    var shortcutsPaused: Bool = ShortcutManager.shared.isPaused

    init() {
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = AppState.shared.isGenerating
            _ = AppState.shared.recentGenerations
            _ = AppState.shared.buckets
            _ = ShortcutManager.shared.isPaused
        } onChange: {
            Task { @MainActor in
                self.updateFromAppState()
                self.observe()
            }
        }
        updateFromAppState()
    }

    private func updateFromAppState() {
        isGenerating = AppState.shared.isGenerating
        hasRecent = !AppState.shared.recentGenerations.isEmpty
        bucketMenuItems = AppState.shared.buckets.map { bucket in
            BucketMenuItem(id: bucket.id, name: bucket.name, allowed: true)
        }
        shortcutsPaused = ShortcutManager.shared.isPaused
    }
}

@MainActor
struct MenuBarLabelView: View {
    /// Signature glyph that WRITES ON while a generation is in flight, then
    /// rests idle. Tied to `AppState.isGenerating` (a single boolean), NOT to
    /// a per-tap notification — the earlier "jump" symptom came from
    /// re-triggering a one-shot draw on every `.signoffMenuBarAppUsed` post,
    /// which threw the glyph into transient mid-draw states across frames and
    /// shifted the status-item width. A `.repeating` drawOn keyed to one
    /// boolean stays in one steady state for the whole generation and only
    /// transitions twice (start / stop), so the menu bar frame never shifts
    /// mid-interaction. Respects Reduce Motion.
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "signature")
            .symbolEffect(
                .drawOn.individually,
                options: .repeating,
                isActive: appState.isGenerating && !reduceMotion
            )
            .task {
                // Open the hidden Settings-context window once at launch. The
                // `Window("…", id: "signoff.settings-context")` scene never
                // instantiates until it is opened via `openWindow` — and until
                // it instantiates, its `.onReceive(.openSettingsShortcutTriggered)`
                // does not subscribe, so every Settings open (popover button +
                // ⌘,) posted into the void. The menu-bar label is the one
                // always-live SwiftUI surface at launch, so it kicks the
                // context window alive; `SettingsContextView.onAppear` then
                // parks it far offscreen.
                openWindow(id: "signoff.settings-context")
            }
    }
}

/// Onboarding presentation is now handled directly by `SignoffMenuContent`,
/// which owns both `@EnvironmentObject private var appState` and
/// `@Environment(\.openWindow)` — the two things needed to observe the
/// `showOnboarding` flag and the `.signoffOnboardingRequested` notification.
