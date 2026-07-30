import SwiftUI
import AppKit
import SignoffCore

/// macOS Settings scene root — Apple HIG toolbar-pane layout via `TabView`.
public struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var fmAvailability = FoundationModelsAvailability.shared
    @ObservedObject private var shortcuts = ShortcutManager.shared

    @AppStorage("signoff.settings.lastPane") private var lastPaneRaw: String = SettingsPane.general.rawValue

    @State private var pendingDestructive: DestructiveConfirm?
    @State private var confirmDestructivePresented = false
    @State private var privacySaveMessage: String?

    // VoiceProfile viewer state
    @State private var showVoiceProfileDetail = false
    @State private var voiceProfileDisplay: VoiceProfileDisplay?

    public init() {}

    public var body: some View {
        TabView(selection: paneBinding) {
            generalPane
                .tabItem { Label(SettingsPane.general.title, systemImage: SettingsPane.general.systemImage) }
                .tag(SettingsPane.general)

            profilePane
                .tabItem { Label(SettingsPane.profile.title, systemImage: SettingsPane.profile.systemImage) }
                .tag(SettingsPane.profile)

            bucketsPane
                .tabItem { Label(SettingsPane.buckets.title, systemImage: SettingsPane.buckets.systemImage) }
                .tag(SettingsPane.buckets)

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
        .frame(minWidth: 640, minHeight: 480)
        .onAppear {
            applyPaneFromNotification(nil)
            fmAvailability.refresh()
            loadVoiceProfile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsShortcutTriggered)) { note in
            applyPaneFromNotification(note)
        }
        .alert(
            pendingDestructive?.title ?? "Confirm",
            isPresented: $confirmDestructivePresented
        ) {
            Button(pendingDestructive?.confirmLabel ?? "Confirm", role: .destructive) {
                if let action = pendingDestructive {
                    performDestructive(action)
                }
                pendingDestructive = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDestructive = nil
            }
        } message: {
            Text(pendingDestructive?.message ?? "")
        }
        .sheet(isPresented: $showVoiceProfileDetail) {
            VoiceProfileDetailView(display: $voiceProfileDisplay)
                .frame(minWidth: 480, minHeight: 400)
        }
    }

    private enum DestructiveConfirm: Equatable {
        case resetShortcutDefaults
        case resetVoiceProfile

        var title: String {
            switch self {
            case .resetShortcutDefaults: return "Reset shortcuts to defaults?"
            case .resetVoiceProfile: return "Reset your voice profile?"
            }
        }

        var message: String {
            switch self {
            case .resetShortcutDefaults:
                return "All bucket chords return to ⌃⌘1–6. Custom bindings will be lost."
            case .resetVoiceProfile:
                return "This will delete all learned patterns, adopted signoffs, and noise signals. Signoff will start learning your voice from scratch."
            }
        }

        var confirmLabel: String {
            switch self {
            case .resetShortcutDefaults: return "Reset"
            case .resetVoiceProfile: return "Reset Voice"
            }
        }
    }

    private func requestDestructive(_ action: DestructiveConfirm) {
        pendingDestructive = action
        confirmDestructivePresented = true
    }

    private func performDestructive(_ action: DestructiveConfirm) {
        switch action {
        case .resetShortcutDefaults: resetShortcutDefaults()
        case .resetVoiceProfile: resetVoiceProfile()
        }
    }

    private func loadVoiceProfile() {
        let profile = VoiceProfile.shared
        voiceProfileDisplay = profile.displaySummary
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
            Section("Appearance") {
                Picker("Color scheme", selection: settingsStringBinding(\.colorSchemeRaw)) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Toggle("Show shortcut hints", isOn: settingsBoolBinding(\.showShortcutHints))
            }
            Section {
                Toggle("Show in menu bar", isOn: showsStatusItemBinding)
                if !appState.settings.showsStatusItem {
                    Button("Quit Signoff", role: .destructive) {
                        NSApp.terminate(nil)
                    }
                }
            } header: {
                Text("Menu bar")
            } footer: {
                Text(menuBarFooterCopy)
                    .foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: settingsBoolBinding(\.launchAtLogin))
            }
            Section {
                LabeledContent("Generations", value: "\(UsageTracker.shared.currentCount)")
            } header: {
                Text("Usage")
            } footer: {
                Text("Signoff is free and open source (MIT). All features are available to everyone — no limits, no subscriptions.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsPane.general.title)
    }

    private var menuBarFooterCopy: String {
        if appState.settings.showsStatusItem {
            return "Hide the icon anytime. Signoff stays Dock-less; shortcuts and Settings (⌘,) keep working."
        }
        return "Menu bar icon hidden. Quit here, or use Signoff → Quit (⌘Q) while Settings is open. Re-open Settings via ⌘, while Signoff is frontmost, or by launching Signoff again from Finder / Spotlight (reopen opens Settings)."
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

    // MARK: - Profile

    private var profilePane: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: profileBinding(\.name))
                TextField("Title", text: profileBinding(\.title))
                TextField("Company", text: profileBinding(\.company))
                TextField("Email", text: profileBinding(\.email))
            }
            Section("Voice") {
                TextField("Self-description", text: profileBinding(\.selfDescription), axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsPane.profile.title)
        .onChange(of: appState.profile) { _, _ in
            try? PersistenceController.shared.context.save()
        }
    }

    // MARK: - Buckets

    private var bucketsPane: some View {
        Form {
            Section {
                ForEach(appState.buckets, id: \.id) { bucket in
                    Toggle(isOn: bucketToggleBinding(bucket)) {
                        Label(bucket.name, systemImage: bucket.iconSymbol)
                    }
                }
            } header: {
                Text("Enabled buckets")
            } footer: {
                Text("All six buckets are available — Standard, Professional, Unhinged, Custom, List, and Footer.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsPane.buckets.title)
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
                            .tint(.signoffAmber)
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
            } footer: {
                Text("Pause when another app needs ⌃⌘ / ⌥⌘, or while remapping Mission Control.")
                    .foregroundStyle(.secondary)
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
            } footer: {
                Text("Click a chord, then press ⌃⌘ or ⌥⌘ plus a digit 1–6. Esc cancels.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset to Defaults (⌃⌘)", role: .destructive) {
                    requestDestructive(.resetShortcutDefaults)
                }
                .buttonStyle(.bordered)
                Button("Use ⌥⌘1–6") {
                    Task { await appState.switchAllShortcutsToOptCmd() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.signoffAmber)
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
                } else if case .modelNotReady = fmAvailability.status {
                    Button("Check Again") {
                        fmAvailability.refresh()
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Text("Apple Intelligence")
            } footer: {
                Text("Signoff drafts with Apple's on-device Foundation Models by default, falling back to a private offline phrasebook when the model isn't ready. Nothing is ever uploaded.")
                    .foregroundStyle(.secondary)
            }

            // MARK: — What I've Learned (VoiceProfile Viewer)
            Section {
                if let display = voiceProfileDisplay {
                    VoiceProfileSummaryView(display: display)

                    Divider().padding(.vertical, 4)

                    HStack(spacing: 12) {
                        Button("View Raw Profile…") {
                            showVoiceProfileDetail = true
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button("Reset My Voice", role: .destructive) {
                            pendingDestructive = .resetVoiceProfile
                            confirmDestructivePresented = true
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Learning not yet started", systemImage: "brain.head.profile")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Grant Accessibility permission to begin silent voice learning from your sent messages.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Accessibility Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            } header: {
                Text("What I've Learned")
            } footer: {
                Text("Your VoiceProfile is built locally from sent messages across Mail, Messages, Slack, and more. It captures your rhythm, formality, and preferred signoffs — never drafts or keystrokes. Encrypted at rest. Never synced. You can reset anytime.")
                    .foregroundStyle(.secondary)
            }

            // MARK: — Learning Status
            Section {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(appState.accessibilityGranted && !VoiceProfile.shared.isLearningPaused ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(appState.accessibilityGranted && !VoiceProfile.shared.isLearningPaused ? "Active" : "Paused")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(Brand.Semantic.textPrimary(for: .light)) // will be overridden by scheme
                        }
                        Text("Observes sent messages in Mail, Messages, Slack to refine your voice profile. Never reads drafts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    if appState.accessibilityGranted {
                        Button("Pause Learning") {
                            VoiceProfile.shared.isLearningPaused = true
                            SilentLearningEngine.shared.pause()
                            loadVoiceProfile()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Grant Accessibility") {
                            let opts = ["AXTrustedCheckOptionPrompt": NSNumber(value: true)] as CFDictionary
                            _ = AXIsProcessTrustedWithOptions(opts)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("Learning Status")
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
            loadVoiceProfile()
        }
    }

    // MARK: - Advanced

    private var advancedPane: some View {
        Form {
            Section("Diagnostics") {
                Toggle("Verbose logging", isOn: settingsBoolBinding(\.verboseLogging))
            }
            Section("Onboarding") {
                Button {
                    NotificationCenter.default.post(name: .signoffRequestOnboardingReplay, object: nil)
                } label: {
                    Label("Re-run Onboarding", systemImage: "sparkles.tv")
                }
                .accessibilityHint("Re-run the 4-step first-launch tour")
            }
            Section("Help") {
                Button {
                    HelpOverlayWindowController.shared.present()
                } label: {
                    Label("Open In-App Help", systemImage: "questionmark.circle.fill")
                }
                .accessibilityHint("Open the in-app Help panel")
                Button {
                    if let url = URL(string: "https://signoffapp.com/help") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open Signoff Help on the Web", systemImage: "safari")
                }
                .accessibilityHint("Open the Signoff help center in your browser")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsPane.advanced.title)
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

    private func profileBinding(_ keyPath: WritableKeyPath<UserProfile, String?>) -> Binding<String> {
        Binding(
            get: { appState.profile[keyPath: keyPath] ?? "" },
            set: { newValue in
                appState.profile[keyPath: keyPath] = newValue.isEmpty ? nil : newValue
            }
        )
    }

    private func profileBinding(_ keyPath: WritableKeyPath<UserProfile, String>) -> Binding<String> {
        Binding(
            get: { appState.profile[keyPath: keyPath] },
            set: { appState.profile[keyPath: keyPath] = $0 }
        )
    }

    private func bucketToggleBinding(_ bucket: Bucket) -> Binding<Bool> {
        Binding(
            get: { bucket.isEnabled },
            set: { newValue in
                bucket.isEnabled = newValue
                bucket.updatedAt = Date()
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
            return "Input Monitoring is blocking the shortcut hub. Grant it in System Settings → Privacy & Security → Input Monitoring, then re-open Signoff."
        }
        return "Space switching on this Mac may be using ⌃⌘1–6. Rebind below, switch all to ⌥⌘, or remap Mission Control in System Settings → Keyboard → Shortcuts."
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

    private func resetShortcutDefaults() {
        Task { await appState.applyShortcutBindings(shortcuts.defaults()) }
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

    private func handleFixAction(_ action: FixAction) {
        switch action {
        case .openSystemSettings(let scheme):
            if let url = URL(string: scheme) { NSWorkspace.shared.open(url) }
        case .openSettings(let pane):
            lastPaneRaw = pane.rawValue
        case .openURL(let url):
            NSWorkspace.shared.open(url)
        case .message:
            break
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

    // MARK: - VoiceProfile helpers

    private func resetVoiceProfile() {
        SilentLearningEngine.shared.reset()
        loadVoiceProfile()
    }
}
