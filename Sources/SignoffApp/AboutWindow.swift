// AboutWindow.swift — Per PERFECTION_PLAN_V2_AUTOPLAN_REVIEW.md TASK-7.
// Brand-aligned About panel shown via `SignoffApp.menuBar → About Signoff`.
// Apple's HIG §Display About Information: window > title > version > credits.

import AppKit
import SwiftUI
import SignoffUI
import SignoffCore

@MainActor
public final class AboutWindowController: NSWindowController {

    public static let shared = AboutWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Signoff"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: AboutRootView())
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    public func present() {
        AppActivation.forForegroundWindow()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        guard let window, !didInstallCloseObserver else { return }
        didInstallCloseObserver = true
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppActivation.returnToAccessoryIfAppropriate()
            }
        }
    }

    private var didInstallCloseObserver = false
}

/// SwiftUI body — tokenized via Brand.* per HIG §Color Tokens.
struct AboutRootView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    private var feedURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String) ?? "https://github.com/arpituppal2/Signoff/releases/latest/download/appcast.json"
    }

    /// Real AppIcon.icns when packaged via `build.sh`; never a decorative SF Symbol.
    private var aboutIconImage: NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        if let named = NSImage(named: "AppIcon"), named.isValid {
            return named
        }
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.hasSuffix(".app") {
            return NSWorkspace.shared.icon(forFile: bundlePath)
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 14) {
            Group {
                if let icon = aboutIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                } else {
                    // Dev / unpackaged runs: the signature mark, not a random SF Symbol.
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Brand.Surface.raised(for: colorScheme))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Brand.ember(for: colorScheme).opacity(0.35), lineWidth: 0.75)
                            )
                            .frame(width: 72, height: 72)
                        Image(systemName: "signature")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(Brand.ember(for: colorScheme))
                    }
                }
            }
            .accessibilityHidden(true)

            // Wordmark removed per user request – no app name text displayed

            Text("Sign every email with intention.")
                .font(.callout)
                .foregroundStyle(Brand.Ink.secondary(for: colorScheme))

            VStack(spacing: 6) {
                Label("On-device generation", systemImage: "lock.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Brand.ember(for: colorScheme))
                Text("Signoffs are drafted by Apple's on-device Foundation Models and stay on this Mac. Nothing is ever uploaded — and Signoff never falls back to canned text; if the model isn't ready, it waits.")
                    .font(.caption)
                    .foregroundStyle(Brand.Ink.secondary(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("On-device generation. Signoffs are drafted by Apple's on-device Foundation Models and stay on this Mac. Nothing is ever uploaded, and Signoff never falls back to canned text; if the model isn't ready, it waits.")

            Divider().overlay(Brand.Surface.divider(for: colorScheme))

            HStack {
                Text("Version")
                Spacer()
                Text(appVersion)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }

            HStack {
                Text("Updates")
                Spacer()
                Text("Signoff · daily check")
                    .font(.caption)
                    .foregroundStyle(Brand.Ink.secondary(for: colorScheme))
            }
            .help("Feed: \(feedURL)")

            HStack(spacing: 12) {
                Button("What's New…") {
                    NotificationCenter.default.post(name: .signoffShowWhatsNew, object: nil)
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Button("Check for Updates…") {
                    NotificationCenter.default.post(name: .signoffCheckForUpdates, object: nil)
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Spacer()
            }

            HStack {
                Text("Made with Swift & Apple Foundation Models")
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(Brand.Ink.tertiary(for: colorScheme))

            Spacer(minLength: 8)

            Text("© 2026 Signoff. MIT licensed.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 480, height: 460)
        .background(Brand.Surface.page(for: colorScheme))
    }
}
