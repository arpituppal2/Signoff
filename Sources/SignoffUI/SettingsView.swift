import SwiftUI
import AppKit
import SignoffCore

/// macOS Settings scene root — Apple HIG toolbar-pane layout via `TabView`.
public struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var fmAvailability = FoundationModelsAvailability.shared
    @ObservedObject private var shortcuts = ShortcutManager.shared

    @AppStorage("signoff.settings.lastPane") private var lastPaneRaw: String = SettingsPane.general.rawValue

    @State private var pendingDestructive: DestructiveConfirm?
    @State private var confirmDestructivePresented = false
    @State private var privacySaveMessage: String?

    // Bucket configuration picker (which voice's settings are shown).
    @State private var configuredBucketID: String = BucketID.custom.rawValue

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
        // Top toolbar tabs — the macOS convention for a utility app's Settings.
        // The `.sidebarAdaptable` sidebar (a System Settings carryover) buried the
        // panes behind a collapse toggle and added friction; top tabs keep every
        // pane one click away and match how focused macOS tools present prefs.
        .tabViewStyle(.automatic)
        .frame(minWidth: 560, idealWidth: 600, minHeight: 460)
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
                return "All bucket chords return to ⌃⌘1–4. Custom bindings will be lost."
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
            Section {
                Toggle("Name", isOn: footerFieldBinding(.name))
                Toggle("Title", isOn: footerFieldBinding(.title))
                Toggle("Company", isOn: footerFieldBinding(.company))
                Toggle("Email", isOn: footerFieldBinding(.email))
            } header: {
                Text("Include in Signoff")
            } footer: {
                Text("The fields you enable are appended to signoffs that carry your signature block.")
                    .foregroundStyle(.secondary)
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
                Text("Four voices — Normal, Professional, Cynical, and Custom.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Configure", selection: $configuredBucketID) {
                    ForEach(appState.buckets, id: \.id) { bucket in
                        Text(bucket.name).tag(bucket.id)
                    }
                }
                .pickerStyle(.menu)

                if let bucket = configuredBucket {
                    bucketConfigView(bucket)
                }
            } header: {
                Text("Voice settings")
            } footer: {
                Text("Each voice is tuned separately. Cynical has its own intensity, and Custom is a footer you write yourself — formatting and image included.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsPane.buckets.title)
    }

    @ViewBuilder
    private func bucketConfigView(_ bucket: Bucket) -> some View {
        switch bucket.id {
        case BucketID.standard.rawValue:
            Text("The everyday voice — no extra settings needed.")
                .font(.callout)
                .foregroundStyle(.secondary)

        case BucketID.professional.rawValue:
            VStack(alignment: .leading, spacing: 4) {
                Slider(value: professionalToneBinding(bucket), in: 0...1) {
                    Text("Formal ⇄ Casual")
                }
                Text(formalityLabel(for: bucket.toneValue ?? 0.5))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case BucketID.unhinged.rawValue:
            Picker("Intensity", selection: cynicalLevelBinding(bucket)) {
                ForEach(UnhingedLevel.allCases, id: \.self) { level in
                    Text(intensityLabel(for: level)).tag(level)
                }
            }
            Toggle("Allow explicit content", isOn: cynicalNSFWBinding(bucket))
            if bucket.nsfwEnabled {
                Text("When on, the Cynical voice may use profanity and adult humor. It stays witty — never hateful.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case BucketID.custom.rawValue:
            RichFooterEditor(bucket: bucket)
            Text("Whatever you write here is exactly what gets copied or pasted — bold, color, and an image included. Press Generate in the menu bar to deliver it.")
                .font(.caption)
                .foregroundStyle(.secondary)

        default:
            EmptyView()
        }
    }

    private var configuredBucket: Bucket? {
        appState.buckets.first(where: { $0.id == configuredBucketID })
            ?? appState.buckets.first
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
                Text("Click a chord, then press ⌃⌘ or ⌥⌘ plus a digit 1–4. Esc cancels.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset to Defaults (⌃⌘)", role: .destructive) {
                    requestDestructive(.resetShortcutDefaults)
                }
                .buttonStyle(.bordered)
                Button("Use ⌥⌘1–4") {
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
            } footer: {
                Text("Signoff drafts with Apple's on-device Foundation Models. Nothing is ever uploaded.")
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
                        .tint(Brand.ember(for: colorScheme))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            } header: {
                Text("What I've Learned")
            } footer: {
                Text("Built locally from sent messages — your rhythm, formality, and preferred signoffs. Never drafts, never keystrokes. Encrypted at rest, never synced.")
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
                                .foregroundStyle(Brand.Ink.primary(for: colorScheme))
                        }
                        Text("Observes sent messages in Mail, Messages, Slack to refine your voice. Never reads drafts.")
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
                        .tint(Brand.ember(for: colorScheme))
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
            Section {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Made by", value: "Arpit Uppal")
            }
            Section {
                Button {
                    if let url = URL(string: "https://buymeacoffee.com/arpituppal") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
                }
                .accessibilityHint("Open Arpit Uppal's Buy Me a Coffee page in your browser")
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

    private func footerFieldBinding(_ field: FooterField) -> Binding<Bool> {
        Binding(
            get: {
                FooterField.decode(appState.profile.footerFieldsRaw)
                    .contains(field.rawValue)
            },
            set: { isOn in
                var fields = FooterField.decode(appState.profile.footerFieldsRaw)
                if isOn { fields.insert(field.rawValue) } else { fields.remove(field.rawValue) }
                appState.profile.footerFieldsRaw = FooterField.encode(fields)
                try? PersistenceController.shared.context.save()
            }
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

    // MARK: - Per-bucket config helpers

    private func professionalToneBinding(_ bucket: Bucket) -> Binding<Double> {
        Binding(
            get: { bucket.toneValue ?? 0.5 },
            set: { newValue in
                bucket.toneValue = newValue
                bucket.updatedAt = Date()
                try? PersistenceController.shared.context.save()
            }
        )
    }

    private func formalityLabel(for toneValue: Double) -> String {
        toneValue > 0.5 ? "Casual-leaning" : (toneValue < 0.5 ? "Formal-leaning" : "Neutral")
    }

    private func cynicalLevelBinding(_ bucket: Bucket) -> Binding<UnhingedLevel> {
        Binding(
            get: { bucket.unhingedLevel ?? .cynical },
            set: { newValue in
                bucket.unhingedLevel = newValue
                bucket.updatedAt = Date()
                try? PersistenceController.shared.context.save()
            }
        )
    }

    private func intensityLabel(for level: UnhingedLevel) -> String {
        switch level {
        case .calm: "Calm"
        case .regular: "Regular"
        case .deranged: "Unhinged"
        case .cynical: "Deadpan"
        }
    }

    private func cynicalNSFWBinding(_ bucket: Bucket) -> Binding<Bool> {
        Binding(
            get: { bucket.nsfwEnabled },
            set: { newValue in
                bucket.nsfwEnabled = newValue
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
        return "Space switching on this Mac may be using ⌃⌘1–4. Rebind below, switch all to ⌥⌘, or remap Mission Control in System Settings → Keyboard → Shortcuts."
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
