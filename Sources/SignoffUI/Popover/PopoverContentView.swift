import SwiftUI
import SignoffCore

/// The single menu-bar popover surface.
/// Compact, functional, native — no marketing elements, no brand gimmicks.
public struct PopoverContentView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var shortcuts = ShortcutManager.shared
    @ObservedObject private var fmAvailability = FoundationModelsAvailability.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dismissedFMCTA = false

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider().overlay(Brand.Semantic.divider(for: scheme))
            bucketList
            Divider().overlay(Brand.Semantic.divider(for: scheme))
            actionBar
            preview
            statusLine
        }
        .padding(14)
        .frame(minWidth: 320, idealWidth: 372, maxWidth: 440)
        .background(Brand.Semantic.surfaceBase(for: scheme))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Signoff popover")
        .accessibilityAction(named: "Generate") {
            guard !appState.isGenerating, appState.selectedBucket != nil else { return }
            Task { await appState.generateNow(shouldAutoPaste: true) }
        }
        .accessibilityAction(named: "Copy last") {
            guard !appState.recentGenerations.isEmpty else { return }
            appState.copyMostRecent()
        }
        .sensoryFeedback(.selection, trigger: appState.selectedBucketId)
        .sensoryFeedback(.success, trigger: appState.generatedText)
        .onAppear { fmAvailability.refresh() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            SignatureMark()
            VStack(alignment: .leading, spacing: 1) {
                Text("Signoff")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.Semantic.textPrimary(for: scheme))
                Text("On-device email signoffs")
                    .font(.caption2)
                    .foregroundStyle(Brand.Semantic.textTertiary(for: scheme))
            }

            Spacer(minLength: 4)

            PrivacyBadge()
                .tint(Brand.amber(for: scheme))
        }
    }

    // MARK: - Bucket List

    private var bucketList: some View {
        VStack(spacing: 2) {
            if appState.buckets.isEmpty {
                Text("No buckets — open Settings to seed defaults.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(appState.buckets, id: \.id) { bucket in
                    BucketRowView(
                        bucket: bucket,
                        isSelected: bucket.id == appState.selectedBucketId,
                        toneLabel: bucket.toneLabel,
                        action: { appState.selectedBucketId = bucket.id }
                    )
                }
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                Task { await appState.generateNow(shouldAutoPaste: true) }
            } label: {
                Label("Generate", systemImage: "signature")
                    .symbolEffect(.pulse, options: .repeating, isActive: appState.isGenerating && !reduceMotion)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.amber(for: scheme))
            .disabled(appState.isGenerating || appState.selectedBucket == nil)
            .accessibilityHint("Generate a signoff in the selected bucket. Shortcut Control-Command-1.")

            Button {
                appState.copyMostRecent()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .disabled(appState.recentGenerations.isEmpty)
            .accessibilityHint("Copy the most recent signoff to the clipboard.")

            if appState.isGenerating {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Generating signoff")
            }
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        if let storeFailure = failureFromStoreRecovery(appState.storeRecovery) {
            ErrorFixCard(
                failure: storeFailure,
                onAction: handleFixAction,
                onDismiss: { appState.storeRecovery = nil }
            )
        } else if let txt = appState.generatedText, !appState.isGenerating {
            SignatureCardView(text: txt, providerKind: appState.lastProviderKind)
                .transition(.opacity.combined(with: .move(edge: .top)))
        } else if appState.isGenerating {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Drafting on-device…")
                    .font(.callout)
                    .foregroundStyle(Brand.Semantic.textSecondary(for: scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .accessibilityLabel("Generating signoff")
        } else if shouldShowFMAvailabilityCard {
            ErrorFixCard(
                failure: .fmUnavailable,
                onAction: handleFixAction,
                onDismiss: { dismissedFMCTA = true }
            )
        } else {
            emptyPreviewState
        }
    }

    /// First-impression placeholder before the first generate. Quiet, on-brand,
    /// tells the user exactly what to press.
    private var emptyPreviewState: some View {
        VStack(spacing: 8) {
            Image(systemName: "character.cursor.ibeam")
                .font(.title3)
                .foregroundStyle(Brand.amber(for: scheme).opacity(0.7))
                .accessibilityHidden(true)
            Text("Press Generate for a signoff ready to paste.")
                .font(.callout)
                .foregroundStyle(Brand.Semantic.textSecondary(for: scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .accessibilityLabel("No signoff yet. Press Generate.")
    }

    private var shouldShowFMAvailabilityCard: Bool {
        guard !dismissedFMCTA else { return false }
        switch fmAvailability.status {
        case .appleIntelligenceNotEnabled, .modelNotReady: return true
        default: return false
        }
    }

    // MARK: - Status Line

    @ViewBuilder
    private var statusLine: some View {
        if failureFromStoreRecovery(appState.storeRecovery) != nil {
            EmptyView()
        } else if appState.persistence.isEphemeral {
            ephemeralStoreBanner
        } else if !shortcuts.boundShortcutConflicts.isEmpty {
            conflictBanner
        } else if let notice = appState.lastStatus {
            dismissableStatus(notice)
        } else {
            HStack(spacing: 12) {
                permissionStatus
                usageCount
                #if DEBUG
                debugLatency
                #endif
            }
            .font(.caption)
            .foregroundStyle(Brand.Semantic.textSecondary(for: scheme))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var permissionStatus: some View {
        if !appState.inputMonitoringGranted || !appState.accessibilityGranted {
            HStack(spacing: 6) {
                if !appState.inputMonitoringGranted {
                    Image(systemName: "keyboard")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("Input Monitoring not granted")
                }
                if !appState.accessibilityGranted {
                    Image(systemName: "cursorarrow")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("Accessibility not granted")
                }
            }
            .accessibilityLabel("Permissions needed")
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var usageCount: some View {
        let tracker = UsageTracker.shared
        if tracker.isOnPaidTier {
            Text("Unlimited")
                .foregroundStyle(.green)
        } else {
            Text("\(tracker.remainingFreeCount)/\(UsageTracker.freeLimit) free")
                .foregroundStyle(tracker.remainingFreeCount < 10 ? Color.orange : .secondary)
                .font(.caption.monospacedDigit())
        }
    }

    @ViewBuilder
    private var debugLatency: some View {
        if let ms = appState.lastLatencyMs, let kind = appState.lastProviderKind {
            Text("· \(kind.badgeTitle) \(ms)ms")
        } else {
            EmptyView()
        }
    }

    private var ephemeralStoreBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text("Temporary store — changes won't persist")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .statusLine()
        .accessibilityElement(children: .combine)
    }

    private var conflictBanner: some View {
        Button {
            NotificationCenter.default.post(
                name: .openSettingsShortcutTriggered,
                object: SettingsPane.shortcuts
            )
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("Shortcut conflict — open Settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .statusLine()
        }
        .buttonStyle(.plain)
    }

    private func dismissableStatus(_ notice: GenerationStatusNotice) -> some View {
        Button {
            appState.dismissGenerationStatus()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(notice.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .statusLine()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func failureFromStoreRecovery(_ recovery: StoreRecovery?) -> SignoffFailure? {
        switch recovery {
        case .resetCorruptStore: return .storeCorrupt
        case .inMemoryFallback: return .storeInMemoryFallback
        case .none: return nil
        }
    }

    private func handleFixAction(_ action: FixAction) {
        switch action {
        case .openSystemSettings(let scheme):
            if let url = URL(string: scheme) { NSWorkspace.shared.open(url) }
        case .openSettings(let pane):
            NotificationCenter.default.post(name: .openSettingsShortcutTriggered, object: pane)
        case .openURL(let url):
            NSWorkspace.shared.open(url)
        case .message: break
        }
    }
}

// MARK: - Bucket Row

public struct BucketRowView: View {
    public let bucket: Bucket
    public let isSelected: Bool
    public let toneLabel: String
    public let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var isHovered = false

    public init(bucket: Bucket, isSelected: Bool, toneLabel: String, action: @escaping () -> Void) {
        self.bucket = bucket
        self.isSelected = isSelected
        self.toneLabel = toneLabel
        self.action = action
    }

    public var body: some View {
        let hint = shortcutHintForBucket(bucket.id)
        let accent = Brand.accent(for: bucket.id, scheme: scheme)
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: bucket.iconSymbol)
                    .font(.body.weight(.medium))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? Brand.amber(for: scheme) : accent)
                    .symbolEffect(.bounce, value: isSelected)

                VStack(alignment: .leading, spacing: 1) {
                    Text(bucket.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Brand.Semantic.textPrimary(for: scheme))
                    Text(toneLabel)
                        .font(.caption)
                        .foregroundStyle(Brand.Semantic.textTertiary(for: scheme))
                        .textCase(.lowercase)
                }

                Spacer(minLength: 4)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(Brand.amber(for: scheme))
                        .accessibilityHidden(true)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Brand.Layout.controlCornerRadius, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Brand.Layout.controlCornerRadius, style: .continuous)
                    .stroke(isSelected ? Brand.amber(for: scheme).opacity(0.35) : .clear,
                            lineWidth: Brand.Layout.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(hint)
        .onHover { h in isHovered = h }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .accessibilityLabel("\(bucket.name) bucket")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(toneLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var backgroundFill: Color {
        if isSelected {
            return Brand.Semantic.surfaceSelected(for: scheme)
        }
        if isHovered {
            return Brand.Semantic.surfaceHover(for: scheme)
        }
        return .clear
    }

    private func shortcutHintForBucket(_ id: String) -> String {
        let manager = ShortcutManager.shared
        let bindings = manager.decode(AppState.shared.settings.bucketShortcutsJSON)
        if let binding = bindings.first(where: { $0.bucketId == id }) {
            let mod = binding.modifier == "optCmd" ? "⌥⌘" : "⌃⌘"
            return "Shortcut: \(mod)\(binding.digitKey) — Click to select, then Generate"
        }
        return "Click to select, then Generate"
    }
}

// MARK: - Signature Mark

/// The Signoff wordmark glyph — an amber ink underline finishing a pen stroke.
/// Reads as a signed-off mark rather than a generic SF Symbol icon.
public struct SignatureMark: View {
    @Environment(\.colorScheme) private var scheme

    public init() {}

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Brand.Layout.controlCornerRadius, style: .continuous)
                .fill(Brand.Semantic.surfaceElevated(for: scheme))
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.Layout.controlCornerRadius, style: .continuous)
                        .stroke(Brand.amber(for: scheme).opacity(0.35), lineWidth: Brand.Layout.hairline)
                )
                .frame(width: 30, height: 30)

            // A penUpDown stroke + amber underline accent.
            VStack(spacing: 0) {
                Image(systemName: "signature")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Brand.amber(for: scheme))
                    .offset(y: -1)
            }
            .frame(width: 30, height: 30)
        }
        .accessibilityHidden(true)
    }
}
