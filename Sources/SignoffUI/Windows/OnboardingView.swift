import SwiftUI
import SignoffCore
import AppKit
import ServiceManagement

/// First-run onboarding for Signoff.
///
/// Minimal required configuration: launch-at-login, shortcut hints, and a
/// quick demo so the user can test the feature immediately. No voice picker,
/// no footer editor — those live in Settings where power users can iterate.
@MainActor
public struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismissWindow) private var dismissWindow

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.Layout.spacingL) {
                header
                howToUse
                togglesSection
                Spacer(minLength: Brand.Layout.spacingM)
                permissionNote
                actionRow
            }
            .padding(Brand.Layout.spacingXL)
            .frame(maxWidth: 480)
        }
        .padding(.vertical, Brand.Layout.spacingL)
        .background(Brand.Surface.page(for: scheme))
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Brand.Layout.spacingS) {
            HStack(spacing: Brand.Layout.spacingS) {
                Image(systemName: "signature")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Brand.ember(for: scheme))
                Text("Welcome to Signoff")
                    .font(Brand.Typography.display)
                    .foregroundStyle(Brand.Ink.primary(for: scheme))
            }
            Text("Signoff drafts a fresh email or chat signoff on your Mac’s on-device model and pastes it at your cursor. Nothing leaves this Mac.")
                .font(Brand.Typography.callout)
                .foregroundStyle(Brand.Ink.secondary(for: scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - How to use

    private var howToUse: some View {
        VStack(alignment: .leading, spacing: Brand.Layout.spacingS) {
            Label("How to use", systemImage: "hand.point.left")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Brand.Ink.primary(for: scheme))

            Text("Pick a voice (left column in the menu bar popover), then hit Generate & Paste — or just press ⌃⌥1 for Normal, ⌃⌥2 for Professional, or ⌃⌥3 for Cynical. No setup needed.")
                .font(Brand.Typography.callout)
                .foregroundStyle(Brand.Ink.secondary(for: scheme))
                .fixedSize(horizontal: false, vertical: true)

            Button("Try it now →") {
                NotificationCenter.default.post(name: .toggleMenuBarPopover, object: nil)
                NotificationCenter.default.post(name: .signoffMenuBarAppUsed, object: nil)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Optional toggles

    private var togglesSection: some View {
        VStack(alignment: .leading, spacing: Brand.Layout.spacingS) {
            Toggle(isOn: launchAtLoginBinding) {
                Label("Launch at login", systemImage: "power.dotted")
            }
            Toggle(isOn: showHintsBinding) {
                Label("Show shortcut hints", systemImage: "keyboard")
            }
        }
    }

    // MARK: - Permission note

    private var permissionNote: some View {
        HStack(alignment: .top, spacing: Brand.Layout.spacingS) {
            Image(systemName: "lock.shield.fill")
                .font(.body)
                .foregroundStyle(Brand.ember(for: scheme))
            VStack(alignment: .leading, spacing: 2) {
                Text("Private on-device generation")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Brand.Ink.primary(for: scheme))
                Text("Uses Apple’s Foundation Models. Your text never leaves this Mac.")
                    .font(Brand.Typography.caption1)
                    .foregroundStyle(Brand.Ink.secondary(for: scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Brand.Layout.spacingM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Brand.Layout.radiusM, style: .continuous)
                .fill(Brand.Surface.card(for: scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Brand.Layout.radiusM, style: .continuous)
                .stroke(Brand.Surface.divider(for: scheme), lineWidth: Brand.Layout.hairline)
        )
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: Brand.Layout.spacingS) {
            Button("Skip for now") {
                appState.markOnboardingCompleted()
                dismissWindow()
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                finish()
            } label: {
                Label("Get started", systemImage: "arrow.right")
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.ember(for: scheme))
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    private func finish() {
        appState.markOnboardingCompleted()
        dismissWindow()
    }

    // MARK: - Bindings

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.launchAtLogin },
            set: { newValue in
                appState.settings.launchAtLogin = newValue
                appState.settings.updatedAt = Date()
                try? PersistenceController.shared.context.save()
                applyLaunchAtLogin(newValue)
            }
        )
    }

    private var showHintsBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.showShortcutHints },
            set: { newValue in
                appState.settings.showShortcutHints = newValue
                appState.settings.updatedAt = Date()
                try? PersistenceController.shared.context.save()
            }
        )
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            NSLog("⚠️ Launch-at-login %@ failed: %@", String(describing: error))
        }
    }
}
