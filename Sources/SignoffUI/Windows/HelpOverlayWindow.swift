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

    private init() {}

    public func present() {
        // Keep the app Dock-less (accessory). Activating is enough to float the
        // Help window above other apps without a Dock icon.
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
    }
}

struct HelpOverlayRootView: View {
    @State private var search: String = ""
    @Environment(\.colorScheme) private var scheme

    private var entries: [(topic: String, body: String)] {
        return [
        ("⌃⌥1–3", "Global generate shortcuts (Control-Option + digit). 1 Normal · 2 Professional · 3 Cynical. Works from any text field — no popover needed. Rebind under Settings → Shortcuts, or switch all to ⌥⌘1–3 if ⌃⌥ clashes."),
        ("⌃⌥` opens menu bar", "Press Control-Option-backtick from anywhere to open the Signoff menu bar without clicking the icon."),
        ("⌃⌥1 generates", "Press ⌃⌥1 from any text field. Signoff drafts the signoff on-device and pastes it at the cursor. Turn auto-paste off in Settings → General → Auto-paste on shortcut to copy only."),
        ("Copy last", "⌃⇧C re-copies your most recent signoff without generating a new one."),
        ("After signoff", "Settings → General → After signoff lets you type a line that always appears below your paste — pronouns, a phone number, or a tagline. Leave it blank for just the signoff."),
        ("On-device generation", "Signoffs are drafted by Apple's on-device Foundation Models and stay on your Mac. Nothing is ever uploaded."),
        ("Accessibility", "Signoff needs Accessibility to paste without switching focus. Open Privacy & Security → Accessibility to enable."),
        ("Input Monitoring", "Global shortcuts (⌃⌥1–3) need Input Monitoring — separate from Accessibility. Open Privacy & Security → Input Monitoring and enable Signoff."),
        ("Apple Intelligence", "On-device drafting runs when Apple Intelligence is available. Enable it in System Settings → Apple Intelligence & Siri for live generation."),
        ("Free and open source", "Signoff is free and open source under the MIT license. All features are available to everyone — no limits, no Pro, no subscriptions."),
        ("What's New", "Help menu → What's New… opens the changelog. Check for Updates… checks our appcast feed for new versions."),
        ("Updates", "Signoff checks for updates daily when a feed URL is configured. Check manually from About or Help → Check for Updates…"),
        ("Quit", "Settings → General → Quit, or ⌘Q while Settings is open. The menu bar power icon also quits. Signoff stays Dock-less and runs in the background until you quit."),
        ("Hide menu bar icon", "Settings → General → Show in menu bar. When hidden, quit via Settings → General or ⌘Q while Settings is open. Re-open Settings with ⌃⌘, or by launching Signoff again.")
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
            // Title bar with the wordmark.
            HStack(spacing: 10) {
                Text("Help")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.Ink.primary(for: scheme))
                Spacer()
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Brand.Ink.tertiary(for: scheme))
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
                    RoundedRectangle(cornerRadius: Brand.Layout.radiusS, style: .continuous)
                        .fill(Brand.Surface.card(for: scheme))
                )
                .frame(maxWidth: 220)
            }
            .padding(14)
            .background(Brand.Surface.page(for: scheme))

            Divider().overlay(Brand.Surface.divider(for: scheme))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(filteredEntries, id: \.topic) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.topic)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Brand.Ink.primary(for: scheme))
                            Text(entry.body)
                                .font(.callout)
                                .foregroundStyle(Brand.Ink.secondary(for: scheme))
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
        .background(Brand.Surface.page(for: scheme))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Signoff Help")
    }
}
