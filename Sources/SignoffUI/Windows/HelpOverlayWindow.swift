// HelpOverlayWindow.swift — DX-EXP-4. Per DX EXPANSION Pass 3 + Design Pass 3.
// Off-line-cached in-app Help reachable from menu-bar Help menu (currently
// only opens `Signoff Help` browser URL). Apple HIG:
//   - Help menu is anchored to right of standard menu items.
//   - Cmd-? shortcut (already wired by SignoffApp's CommandGroup(replacing: .help)).
//   - Native NSPanel — non-modal; floats above content.

import AppKit
import SwiftUI
import SignoffCore

@MainActor
public final class HelpOverlayWindowController {
    public static let shared = HelpOverlayWindowController()

    private var window: NSWindow?
    private var didInstallCloseObserver = false

    private init() {}

    public func present() {
        // Activate so Help isn't buried under other apps (LSUIElement accessory).
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let rect = NSRect(x: 0, y: 0, width: 560, height: 480)
        let w = NSWindow(contentRect: rect,
                         styleMask: [.titled, .closable, .resizable],
                         backing: .buffered,
                         defer: false)
        w.title = "Signoff Help"
        w.isReleasedWhenClosed = false
        w.center()
        w.contentView = NSHostingView(rootView: HelpOverlayRootView())
        w.makeKeyAndOrderFront(nil)
        self.window = w
        guard !didInstallCloseObserver else { return }
        didInstallCloseObserver = true
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: w,
            queue: .main
        ) { _ in
            Task { @MainActor in
                let hasVisibleKeyableWindow = NSApp.windows.contains { window in
                    window.isVisible
                        && window.canBecomeKey
                        && window.styleMask.contains(.titled)
                }
                if !hasVisibleKeyableWindow, NSApp.activationPolicy() != .accessory {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }
}

struct HelpOverlayRootView: View {
    @State private var search: String = ""
    @Environment(\.colorScheme) private var scheme

    private var entries: [(topic: String, body: String)] {
        return [
        ("⌃⌘1–6", "Global generate shortcuts (Control-Command + digit). 1 Standard · 2 Professional · 3 Unhinged · 4 Custom · 5 List · 6 Footer. Works from any text field — no popover needed. Rebind under Settings → Shortcuts."),
        ("⌃⌘1 generates", "Press ⌃⌘1 from any text field. Signoff drafts the signoff on-device and copies it to your clipboard — press ⌘V to paste at the cursor."),
        ("Copy last", "⇧⌘C re-copies your most recent signoff without generating a new one."),
        ("On-device generation", "Signoffs are drafted by Apple's on-device Foundation Models and stay on your Mac. When Apple Intelligence isn't ready, a private offline phrasebook keeps you going — nothing is ever uploaded."),
        ("Accessibility", "Signoff needs Accessibility to paste without switching focus. Open Privacy & Security → Accessibility to enable."),
        ("Input Monitoring", "Global shortcuts (⌃⌘1–6) need Input Monitoring — separate from Accessibility. Open Privacy & Security → Input Monitoring and enable Signoff."),
        ("Apple Intelligence", "On-device drafting runs when Apple Intelligence is available. Enable it in System Settings → Apple Intelligence & Siri for live generation."),
        ("Free and open source", "Signoff is free and open source under the MIT license. All features are available to everyone — no Pro, no licenses, no quotas."),
        ("What's New", "Help menu → What's New… opens the changelog. Check for Updates… checks our appcast feed for new versions."),
        ("Updates", "Signoff checks for updates daily when a feed URL is configured. Check manually from About or Help → Check for Updates…"),
        ("Hide menu bar icon", "Settings → General → Show in menu bar. When hidden, Quit is in that pane (or ⌘Q while Settings is open). Re-open Settings with ⌘, while Signoff is frontmost, or by launching Signoff again from Finder / Spotlight. The app stays Dock-less.")
        ]
    }

    var filteredEntries: [(topic: String, body: String)] {
        guard !search.isEmpty else { return entries }
        return entries.filter { entry in
            entry.topic.localizedCaseInsensitiveContains(search)
                || entry.body.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar with the signature mark + wordmark.
            HStack(spacing: 10) {
                SignatureMark()
                Text("Help")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.Semantic.textPrimary(for: scheme))
                Spacer()
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Brand.Semantic.textTertiary(for: scheme))
                        .accessibilityHidden(true)
                    TextField("Search help…", text: $search)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .accessibilityLabel("Search help")
                        .accessibilityHint("Filter help topics by keyword")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Brand.Layout.controlCornerRadius, style: .continuous)
                        .fill(Brand.Semantic.surfaceElevated(for: scheme))
                )
                .frame(maxWidth: 220)
            }
            .padding(14)
            .background(Brand.Semantic.surfaceBase(for: scheme))

            Divider().overlay(Brand.Semantic.divider(for: scheme))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(filteredEntries, id: \.topic) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.topic)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Brand.Semantic.textPrimary(for: scheme))
                            Text(entry.body)
                                .font(.callout)
                                .foregroundStyle(Brand.Semantic.textSecondary(for: scheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(entry.topic)
                        .accessibilityHint(entry.body)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 560, height: 480)
        .background(Brand.Semantic.surfaceBase(for: scheme))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Signoff Help")
    }
}
