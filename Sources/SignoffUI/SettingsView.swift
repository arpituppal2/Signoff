import SwiftUI
import AppKit
import SignoffCore
import ServiceManagement

/// macOS Settings scene root — Apple HIG toolbar-pane layout via `TabView`.
public struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var fmAvailability = FoundationModelsAvailability.shared
    @ObservedObject private var shortcuts = ShortcutManager.shared

    @AppStorage("signoff.settings.lastPane") private var lastPaneRaw: String = SettingsPane.general.rawValue

    @State private var privacySaveMessage: String?
    @State private var afterSignoffDoc: NSAttributedString = NSAttributedString()
    @State private var afterSignoffHeight: CGFloat = 160
    @StateObject private var footerFormatter = RichTextFormatterController()

    // Accessibility settings via NSWorkspace (no SwiftUI env keys on macOS yet)
    @State private var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    @State private var increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

    public init() {}

    public var body: some View {
        TabView(selection: paneBinding) {
            generalPane
                .tabItem { Label(SettingsPane.general.title, systemImage: SettingsPane.general.systemImage) }
                .tag(SettingsPane.general)

            shortcutsPane
                .tabItem { Label(SettingsPane.shortcuts.title, systemImage: SettingsPane.shortcuts.systemImage) }
                .tag(SettingsPane.shortcuts)

            privacyPane
                .tabItem { Label(SettingsPane.privacy.title, systemImage: SettingsPane.privacy.systemImage) }
                .tag(SettingsPane.privacy)

            advancedPane
                .tabItem { Label(SettingsPane.advanced.title, systemImage: SettingsPane.advanced.systemImage) }
                .tag(SettingsPane.advanced)
        }
        .tabViewStyle(.automatic)
        .frame(minWidth: 560, idealWidth: 600, minHeight: 460)
        .onAppear {
            applyPaneFromNotification(nil)
            fmAvailability.refresh()
            afterSignoffDoc = appState.settings.afterSignoffAttributedString
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsShortcutTriggered)) { note in
            applyPaneFromNotification(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)) { _ in
            reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        }
    }

    private var paneBinding: Binding<SettingsPane> {
        Binding(
            get: { SettingsPane.resolve(lastPaneRaw) },
            set: { lastPaneRaw = $0.rawValue }
        )
    }

    // MARK: - General

    private var generalPane: some View {
        Form {
            Section {
                Picker("Color scheme", selection: settingsStringBinding(\.colorSchemeRaw)) {
                    Text("Match System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Toggle("Show shortcut hints", isOn: settingsBoolBinding(\.showShortcutHints))
            } header: {
                Text("Appearance")
            }

            Section {
                Toggle("Show Signoff in menu bar", isOn: showsStatusItemBinding)
                Toggle("Launch at login", isOn: launchAtLoginBinding)
            } header: {
                Text("Menu bar")
            }

            Section {
                RichTextToolbar(formatter: footerFormatter)
                    .padding(.bottom, 2)
                RichTextEditor(document: $afterSignoffDoc, placeholder: "e.g. Arpit Uppal\narpit@example.com\n+1 (555) 010-2024", formatter: footerFormatter, onMeasuredHeight: { afterSignoffHeight = max(160, min($0, 320)) })
                    .frame(minHeight: 96, idealHeight: afterSignoffHeight, maxHeight: 320)
                    .overlay(
                        RichTextPlaceholder("e.g. Arpit Uppal\narpit@example.com\n+1 (555) 010-2024", document: afterSignoffDoc)
                    )
                    .onChange(of: afterSignoffDoc) { _, newValue in
                        appState.settings.afterSignoffAttributedString = newValue
                        appState.settings.updatedAt = Date()
                        try? PersistenceController.shared.context.save()
                    }
            } header: {
                Text("After signoff")
            } footer: {
                Text("Appended below every generated signoff. Drag the bottom edge or add lines to grow it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Replace previous signoff on retrigger", isOn: settingsBoolBinding(\.rapidReplaceEnabled))
                if appState.settings.rapidReplaceEnabled {
                    Picker("Replace window", selection: settingsIntBinding(\.rapidReplaceCooldownSeconds)) {
                        Text("2s").tag(2)
                        Text("3s").tag(3)
                        Text("5s").tag(5)
                        Text("10s").tag(10)
                        Text("15s").tag(15)
                        Text("30s").tag(30)
                        Text("60s").tag(60)
                    }
                }
            } header: {
                Text("Rapid replace")
            }

            Section {
                Toggle("Auto-paste on shortcut", isOn: settingsBoolBinding(\.shortcutAutoPaste))
            } header: {
                Text("Shortcuts")
            }

            Section {
                LabeledContent("Generations", value: "\(UsageTracker.shared.currentCount)")
            } header: {
                Text("Usage")
            }

            Section {
                Button("Quit Signoff", role: .destructive) {
                    NSApp.terminate(nil)
                }
            } header: {
                Text("Quit")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsPane.general.title)
    }

    private var showsStatusItemBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.showsStatusItem },
            set: { newValue in
                appState.settings.showsStatusItem = newValue
                appState.settings.updatedAt = Date()
                try? PersistenceController.shared.context.save()
                NotificationCenter.default.post(name: .signoffShowsStatusItemDidChange, object: nil)
            }
        )
    }

    /// Persist the bool AND register/unregister the login item so the toggle
    /// actually takes effect. Previously the pre-existing row was write-only.
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

    private func applyLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            NSLog("⚠️ Launch-at-login toggle failed: %@", String(describing: error))
        }
    }

    // MARK: - Shortcuts

    private var shortcutsPane: some View {
        Form {
            if !shortcuts.boundShortcutConflicts.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Shortcut conflict", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text(conflictBannerMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Switch all to ⌥⌘") {
                                Task { await appState.switchAllShortcutsToOptCmd() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Brand.ember(for: colorScheme))
                            Button("Open Mission Control Shortcuts…") {
                                openKeyboardShortcutsSettings()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Shortcut conflict. \(conflictBannerMessage)")
                }
            }

            Section {
                Toggle("Pause shortcuts", isOn: pauseShortcutsBinding)
                if shortcuts.isPaused {
                    Text("Global chords are ignored until you resume. Menu and popover Generate still work.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                ForEach(displayedBindings, id: \.bucketId) { binding in
                    LabeledContent {
                        ShortcutRecorderView(
                            currentDigitKey: binding.digitKey,
                            currentModifier: binding.modifier,
                            onCommit: { digit, modifier in
                                commitShortcut(bucketId: binding.bucketId,
                                               digitKey: digit,
                                               modifier: modifier)
                            }
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bucketName(for: binding.bucketId))
                            if let conflict = shortcuts.boundShortcutConflicts[binding.digitKey] {
                                Text(conflict)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            } header: {
                Text("Bucket shortcuts")
            }

            Section {
                Button("Use ⌥⌘1–3") {
                    Task { await appState.switchAllShortcutsToOptCmd() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.ember(for: colorScheme))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsPane.shortcuts.title)
        .onAppear {
            Task { await appState.registerShortcutBindings() }
        }
    }

    // MARK: - Privacy

    private var privacyPane: some View {
        Form {
            Section {
                LabeledContent("On-device model") {
                    Label(fmAvailability.userFacingTitle, systemImage: fmSymbol(for: fmAvailability.status))
                        .foregroundStyle(fmAvailability.isUsable ? .green : .secondary)
                }
                Text(fmAvailability.userFacingCause)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if fmAvailability.shouldOpenAppleIntelligenceSettings {
                    Button("Open Apple Intelligence Settings…") {
                        NSWorkspace.shared.open(FoundationModelsAvailability.appleIntelligenceSettingsURL)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.ember(for: colorScheme))
                } else if case .modelNotReady = fmAvailability.status {
                    Button("Check Again") {
                        fmAvailability.refresh()
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Text("Apple Intelligence")
            }

            Section {
                VStack(alignment: .leading, spacing: Brand.Layout.spacingS) {
                    permissionRow(
                        title: "Accessibility",
                        why: "to paste a signoff at your cursor without switching apps.",
                        granted: appState.accessibilityGranted,
                        url: AccessibilityAccess.systemSettingsURL
                    )
                    permissionRow(
                        title: "Input Monitoring",
                        why: "for the global ⌃⌥N shortcuts that work from any app.",
                        granted: appState.inputMonitoringGranted,
                        url: InputMonitoringAccess.systemSettingsURL
                    )
                }
            } header: {
                Text("Permissions")
            }

            if let privacySaveMessage {
                Section {
                    Label(privacySaveMessage, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsPane.privacy.title)
        .onAppear {
            fmAvailability.refresh()
        }
    }

    @ViewBuilder
    private func permissionRow(title: String, why: String, granted: Bool, url: URL) -> some View {
        HStack(spacing: Brand.Layout.spacingS) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                Text("\(title) — \(why)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !granted {
                Button("Open…") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Advanced

    private var advancedPane: some View {
        Form {
            Section {
                LabeledContent("Version", value: appVersion)
                LabeledContent("macOS target", value: "26.0 (Apple Intelligence required)")
            } header: {
                Text("About")
            }

            Section {
                Button {
                    appState.resetOnboardingForReplay()
                    NotificationCenter.default.post(name: .signoffOnboardingRequested, object: nil)
                } label: {
                    Label("Re-run onboarding", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            } header: {
                Text("Setup")
            }

            Section {
                Toggle("Verbose logging", isOn: settingsBoolBinding(\.verboseLogging))
            } header: {
                Text("Diagnostics")
            }

            Section {
                Button {
                    if let url = URL(string: "https://buymeacoffee.com/arpituppal") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Support Signoff", systemImage: "cup.and.saucer.fill")
                }
                .buttonStyle(.bordered)
                Link("View source on GitHub", destination: URL(string: "https://github.com/arpituppal/Signoff") ?? URL(fileURLWithPath: "/"))
                    .font(.callout)
            } header: {
                Text("Support")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsPane.advanced.title)
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    // MARK: - Bindings

    private func settingsBoolBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { appState.settings[keyPath: keyPath] },
            set: { newValue in
                appState.settings[keyPath: keyPath] = newValue
                appState.settings.updatedAt = Date()
                try? PersistenceController.shared.context.save()
            }
        )
    }

    private func settingsStringBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, String>) -> Binding<String> {
        Binding(
            get: { appState.settings[keyPath: keyPath] },
            set: { newValue in
                appState.settings[keyPath: keyPath] = newValue
                appState.settings.updatedAt = Date()
                try? PersistenceController.shared.context.save()
            }
        )
    }

    private func settingsIntBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, Int>) -> Binding<Int> {
        Binding(
            get: { appState.settings[keyPath: keyPath] },
            set: { newValue in
                appState.settings[keyPath: keyPath] = newValue
                appState.settings.updatedAt = Date()
                try? PersistenceController.shared.context.save()
            }
        )
    }

    // MARK: - Shortcuts helpers

    private var displayedBindings: [ShortcutManager.BucketBinding] {
        let decoded = shortcuts.decode(appState.settings.bucketShortcutsJSON)
        return decoded.isEmpty ? shortcuts.defaults() : decoded
    }

    private var pauseShortcutsBinding: Binding<Bool> {
        Binding(
            get: { shortcuts.isPaused },
            set: { appState.setShortcutsPaused($0) }
        )
    }

    private var conflictBannerMessage: String {
        let values = shortcuts.boundShortcutConflicts.values
        if values.contains(where: { $0.localizedCaseInsensitiveContains("Input Monitoring") }) {
            return "Input Monitoring is blocking shortcuts. Grant it in System Settings → Privacy & Security → Input Monitoring, then re-open Signoff."
        }
        return "Space switching may be using ⌃⌘1–4. Rebind, switch all to ⌃⌥, or remap Mission Control in System Settings → Keyboard → Shortcuts."
    }

    private func commitShortcut(bucketId: String, digitKey: String, modifier: String) {
        var next = displayedBindings
        if let otherIdx = next.firstIndex(where: { $0.digitKey == digitKey && $0.bucketId != bucketId }),
           let selfIdx = next.firstIndex(where: { $0.bucketId == bucketId }) {
            let displaced = next[selfIdx].digitKey
            next[otherIdx].digitKey = displaced
            next[otherIdx].modifier = next[selfIdx].modifier
        }
        guard let idx = next.firstIndex(where: { $0.bucketId == bucketId }) else { return }
        next[idx].digitKey = digitKey
        next[idx].modifier = modifier
        Task { await appState.applyShortcutBindings(next) }
    }

    private func bucketName(for id: String) -> String {
        appState.buckets.first { $0.id == id }?.name
            ?? BucketID(rawValue: id)?.rawValue.capitalized
            ?? id
    }

    private func openKeyboardShortcutsSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?ShortcutTab",
            "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts",
        ]
        for raw in candidates {
            if let url = URL(string: raw) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }

    private func fmSymbol(for status: FoundationModelsAvailability.Status) -> String {
        switch status {
        case .available: return "checkmark.seal.fill"
        case .appleIntelligenceNotEnabled: return "sparkles"
        case .modelNotReady: return "arrow.down.circle"
        case .deviceNotEligible: return "laptopcomputer.slash"
        case .unavailable, .unsupportedSDK: return "exclamationmark.triangle.fill"
        }
    }

    private func applyPaneFromNotification(_ note: Notification?) {
        if let raw = note?.userInfo?["pane"] as? String {
            lastPaneRaw = SettingsPane.resolve(raw).rawValue
            return
        }
        if let pane = note?.object as? SettingsPane {
            lastPaneRaw = pane.rawValue
        }
    }
}
