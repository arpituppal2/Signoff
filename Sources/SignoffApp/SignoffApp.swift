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
    /// item correctly dims while a generation is in flight, AND so "Copy
    /// Last Signoff" correctly dims when the recent-strip is empty. Without
    /// this bridge `CommandMenu` does not subscribe to `@ObservedObject`
    /// updates the way `View.body` does (CommandMenu lives inside a Scene's
    /// `.commands { ... }` modifier, not inside a View). The reviewer
    /// flagged this in the post-fix review as the only v1.1 nit; addressing
    /// it now keeps the menu's behavior faithful to the popover's.
    @StateObject private var menuState = SignoffMenuState()

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(AppState.shared)
                /* EntitlementManager removed — Signoff is free */
        }
        // HIG "Design > Designing for macOS > Use the menu bar to give people
        // easy access to all the commands they need to do things in your app"
        // — menu-bar-only apps STILL need a standard menu bar so keyboard-only
        // users can drive without ever touching the NSStatusItem. The
        // `CommandMenu("Signoff")` block emits Generate + Copy Last with their
        // `keyboardShortcut(...)` modifiers so macOS auto-displays them on the
        // right side of every menu item, with the modifier order
        // Control → Option → Shift → Command specified by HIG "Input > Custom
        // keyboard shortcuts > List modifier keys in the correct order".
        // The Fixer: this also fixes the right-click context menu's
        // `keyEquivalent` violations — see `buildRightClickMenu` below,
        // which now intentionally drops the key equivalents (per HIG
        // "Input > Context menus": "Show keyboard shortcuts in your app's
        // main menus, not in context menus").
        .commands {
            CommandMenu("Signoff") {
                Button("Generate Signoff") {
                    Task { await AppState.shared.generateNow() }
                }
                .keyboardShortcut("1", modifiers: [.control, .command])
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
                .keyboardShortcut("c", modifiers: [.shift, .command])
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
            // Opens the SwiftUI Settings scene (⌘,) — not a duplicate NSWindow.
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
                Button("Re-run Onboarding") {
                    // Do not open Settings here — it steals focus from the tour panel.
                    NotificationCenter.default.post(name: .signoffRequestOnboardingReplay, object: nil)
                }
            }
        }
    }
}

@MainActor
final class SignoffDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController!

    private var appState: AppState { AppState.shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prefer Info.plist LSUIElement = YES for the shipping bundle.
        // Keep .accessory as a belt-and-suspenders for `swift run` / unsigned
        // SPM launches that may lack the plist key.
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }

        // os_signpost: cold-launch trace for Instruments profiling.
        // SPEC §12 target <400ms from process start to menubar ready.
        let launchSignpost = SignoffSignpost.coldLaunch.makeSignpostID()
        let launchState = SignoffSignpost.coldLaunch.beginInterval("launch", id: launchSignpost)

        // Spec: no MetricKit, no TipKit, no CelebrationCapsule in v1.
        // Clean startup — just prewarm FMF and init state.

        SparkleIntegration.shared.startIfNeeded()

        // Foundation Models — prewarm the on-device language model so the first
        // generation is fast (avoids 2-5s cold-start on macOS 26+). Non-blocking.
        if #available(macOS 26, *) {
            Task.detached(priority: .utility) {
                await GenerationService.shared.prewarmFoundationModels()
            }
        }

        Task {
            do {
                try await appState.initialize()
                statusBarController = StatusBarController(appState: appState)
                statusBarController.install()
                // End cold-launch signpost once menubar is ready
                SignoffSignpost.coldLaunch.endInterval("launch", launchState)
                presentOnboardingIfNeeded()
            } catch {
                NSLog("❌ Signoff init failed: %@", String(describing: error))
                // End signpost even on failure so Instruments doesn't orphan the interval
                SignoffSignpost.coldLaunch.endInterval("launch", launchState)
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(openSettingsScene),
                                               name: .openSettingsShortcutTriggered, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(replayOnboarding),
                                               name: .signoffRequestOnboardingReplay, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(presentA11yExplainer),
                                               name: .signoffNeedsA11yExplainer, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(checkForUpdates),
                                               name: .signoffCheckForUpdates, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showWhatsNew),
                                               name: .signoffShowWhatsNew, object: nil)
    }

    private var onboardingController: OnboardingWindowController?

    /// Single interactive first-run surface: Welcome → Permissions (AX + Input
    /// Monitoring) → Profile (skippable) → Cheat sheet. TipKit tips take over
    /// afterward — the timed FirstLaunchOverlay is not auto-chained (it
    /// duplicated this flow).
    private func presentOnboardingIfNeeded() {
        appState.syncOnboardingFlagFromSettings()
        guard appState.showOnboarding else { return }
        presentOnboardingTour()
    }

    private func presentOnboardingTour() {
        onboardingController?.close()
        AppActivation.forForegroundWindow()
        let controller = OnboardingWindowController()
        onboardingController = controller
        controller.present { [weak self] in
            self?.onboardingController = nil
            self?.appState.syncOnboardingFlagFromSettings()
            AppActivation.returnToAccessoryIfAppropriate()
        }
    }

    @objc private func replayOnboarding() {
        appState.resetOnboardingForReplay()
        presentOnboardingTour()
    }

    @objc private func presentA11yExplainer() {
        // Spec: onboarding handles permissions explanation.
        _ = PasteAutomation.shared.requestPermission()
    }

    @objc private func checkForUpdates() {
        SparkleIntegration.shared.checkForUpdates()
    }

    @objc private func showWhatsNew() {
        SparkleIntegration.shared.showWhatsNew()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Dock-less (LSUIElement): reopen recovers Settings when the menu bar
        // extra is hidden (`AppSettings.showsStatusItem == false`), or when
        // there are no keyable windows.
        let statusHidden = !(statusBarController?.appState.settings.showsStatusItem ?? true)
        if !flag || statusHidden {
            SettingsSceneOpener.open()
        }
        return true
    }

    @objc func openSettingsScene() {
        SettingsSceneOpener.open()
    }
}

@MainActor
public final class StatusBarController {
    public let appState: AppState
    /// Exposed so first-launch tour can anchor above the menu-bar button.
    public let statusItem: NSStatusItem
    private var showsStatusItemObserver: NSObjectProtocol?

    public init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    }

    public func install() {
        statusItem.button?.image = makeGlyph()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleClick(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.toolTip = "Signoff — Press ⌃⌘` to open the popover, or ⌃⌘1–6 for any bucket."
        statusItem.button?.setAccessibilityLabel("Signoff")
        statusItem.button?.setAccessibilityHelp("Opens the Signoff popover. Right-click for Generate, Copy last, Settings, and Help.")
        statusItem.button?.setAccessibilityRole(.button)
        let popover = NSPopover()
        popover.behavior = .transient
        // Single popover surface: PopoverContentView. NSPopover supplies
        // Liquid Glass — content must not wrap another outer material.
        popover.contentViewController = NSHostingController(rootView:
            PopoverContentView(appState: appState)
                /* EntitlementManager removed — Signoff is free */
        )
        self.popover = popover
        buildRightClickMenu()
        // HIG: honor Settings → General “Show in menu bar” (persisted).
        applyShowsStatusItemFromSettings()
        observeShowsStatusItemChanges()
    }

    /// Applies `AppSettings.showsStatusItem` to the live `NSStatusItem`.
    /// When hidden, Quit remains in Settings → General; Settings stays
    /// reachable via `SettingsSceneOpener` / `applicationShouldHandleReopen` /
    /// ⌘, while Signoff is frontmost (Dock-less LSUIElement preserved).
    public func applyShowsStatusItemFromSettings() {
        let show = appState.settings.showsStatusItem
        if !show, let popover, popover.isShown {
            popover.performClose(nil)
        }
        statusItem.isVisible = show
    }

    private func observeShowsStatusItemChanges() {
        guard showsStatusItemObserver == nil else { return }
        showsStatusItemObserver = NotificationCenter.default.addObserver(
            forName: .signoffShowsStatusItemDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyShowsStatusItemFromSettings()
            }
        }
    }

    private var popover: NSPopover!
    private var menu: NSMenu!

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            statusItem.menu = menu
            sender.performClick(nil)
            statusItem.menu = nil
            return
        }
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func buildRightClickMenu() {
        let m = NSMenu()
        // HIG "Input > Context menus": "Show keyboard shortcuts in your app's
        // main menus, not in context menus." Display the actions identically
        // in this right-click menu but DO NOT advertise key equivalents here
        // — they live on the menu bar's `Signoff` submenu via
        // `SignoffApp.commands { CommandMenu("Signoff") { ... } }` so users
        // only see one source of truth. The `keyEquivalent` arguments below
        // are deliberately empty strings (was ",", "q" before the polish pass).
        m.addItem(withTitle: "Generate Signoff", action: #selector(generateShortcut), keyEquivalent: "")
        m.addItem(withTitle: "Copy Last Signoff", action: #selector(copyLastShortcut), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "Settings…", action: #selector(openSettingsShortcut), keyEquivalent: "")
        m.addItem(withTitle: "Signoff Help…", action: #selector(openHelpShortcut), keyEquivalent: "")
        m.addItem(withTitle: "Re-run Onboarding…", action: #selector(reOnboardingShortcut), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "Quit Signoff", action: #selector(quitShortcut), keyEquivalent: "")
        menu = m
    }

    @objc private func generateShortcut() {
        Task { await appState.generateNow() }
    }

    @objc private func copyLastShortcut() {
        guard let last = appState.recentGenerations.first else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(last.text, forType: .string)
    }

    @objc private func openSettingsShortcut() {
        NotificationCenter.default.post(name: .openSettingsShortcutTriggered, object: nil)
    }

    @objc private func openHelpShortcut() {
        HelpOverlayWindowController.shared.present()
    }

    @objc private func reOnboardingShortcut() {
        NotificationCenter.default.post(name: .signoffRequestOnboardingReplay, object: nil)
    }

    @objc private func quitShortcut() {
        NSApp.terminate(nil)
    }

    private func makeGlyph() -> NSImage {
        // Spec §8: menu bar icon is the "signature" SF Symbol.
        // Template image so the system tints for light/dark/high-contrast.
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let symbol = NSImage(
            systemSymbolName: "signature",
            accessibilityDescription: "Signoff"
        )
            ?? NSImage(
                systemSymbolName: "pencil.and.scribble",
                accessibilityDescription: "Signoff"
            )
            ?? NSImage(size: NSSize(width: 18, height: 18))
        let image = symbol.withSymbolConfiguration(config) ?? symbol
        image.isTemplate = true
        return image
    }
}

/// Adopting `@MainActor` here matches `AppState.shared`'s isolation — and
/// the bridge needs to live as long as the `App` instance does. Storing it
/// as `private final class` keeps it Sendable-bound to MainActor so the
/// `.assign(to: &$isGenerating)` call passes Swift 6 StrictConcurrency.
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
