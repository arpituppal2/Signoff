import SwiftUI
import AppKit
import Combine
import os
import SignoffCore
import SignoffUI
import TipKit

/// Single-source-of-truth app glue. v2 spec §21 ship-locked.
@main
struct SignoffApp: App {
    @NSApplicationDelegateAdaptor(SignoffDelegate.self) var delegate
    /// Bridges `AppState.shared.@Published` flags into the CommandMenu's
    /// `.disabled(...)` closures so the Signoff submenu's "Generate Signoff"
    /// item correctly dims while a generation is in flight, AND so "Copy
    /// Last Signoff" correctly dims when the recent-strip is empty.
    @StateObject private var menuState = SignoffMenuState()

    var body: some Scene {
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
                .environmentObject(AppState.shared)
        }
        // Menu bar extra. `.window` (popover) is required — SignoffMenuContent is
        // a rich popover surface (ScrollView, toast overlay, custom button styles,
        // page fills) that an NSMenu (`.menu` style) cannot represent; `.menu`
        // silently strips anything that isn't a menu item.
        MenuBarExtra(content: {
            SignoffMenuContent()
                .environmentObject(AppState.shared)
        }, label: {
            MenuBarLabelView()
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
                SettingsLink()
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

        // Configure TipKit for contextual onboarding
        configureTips()

        let launchSignpost = SignoffSignpost.coldLaunch.makeSignpostID()
        let launchState = SignoffSignpost.coldLaunch.beginInterval("launch", id: launchSignpost)

        SparkleIntegration.shared.startIfNeeded()

        if #available(macOS 26, *) {
            Task.detached(priority: .utility) {
                await GenerationService.shared.prewarmFoundationModels()
            }
        }

        Task {
            do {
                try await appState.initialize()
                SignoffSignpost.coldLaunch.endInterval("launch", launchState)
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
            SettingsSceneOpener.open()
        }
        return true
    }
}

@MainActor
private final class SignoffMenuState: ObservableObject {
    struct BucketMenuItem: Identifiable, Equatable {
        let id: String
        let name: String
        let allowed: Bool
    }

    @Published var isGenerating: Bool = false
    @Published var hasRecent:   Bool = false
    @Published var bucketMenuItems: [BucketMenuItem] = []
    @Published var shortcutsPaused: Bool = ShortcutManager.shared.isPaused

    init() {
        // Subscribe once at App startup; the Combine chain holds the
        // singleton's `AnyPublisher` and tears down with the App.
        AppState.shared.$isGenerating
            .assign(to: &$isGenerating)
        AppState.shared.$recentGenerations
            .map { !$0.isEmpty }
            .assign(to: &$hasRecent)
        AppState.shared.$buckets
            .map { buckets in
                buckets.map { bucket in
                    BucketMenuItem(
                        id: bucket.id,
                        name: bucket.name,
                        allowed: true
                    )
                }
            }
            .assign(to: &$bucketMenuItems)
        ShortcutManager.shared.$isPaused
            .assign(to: &$shortcutsPaused)
    }
}

@MainActor
struct MenuBarLabelView: View {
    /// Static signature glyph — no per-tap animation so the menu bar frame
    /// never shifts width mid-interaction. A draw animation re-triggered on
    /// every `.signoffMenuBarAppUsed` notification caused the menubar item to
    /// jump, which is disqualifying for a pedestal indicator.
    var body: some View {
        Image(systemName: "signature")
    }
}