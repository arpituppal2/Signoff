import SwiftUI
import SignoffCore
import TipKit
import AppKit

/// Menu content for MenuBarExtra — replaces NSPopover per HIG "Display a menu — not a popover".
///
/// Layout: a wide, balanced two-column surface (Voices → Compose) on Liquid Glass
/// materials, with a slim bottom bar carrying status + Settings/Quit. Density is
/// deliberately low — one section per concern, generous spacing, and a single
/// contextual TipKit slot instead of a stack.
@MainActor
public struct SignoffMenuContent: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Toast state for copy confirmation
    @State private var showCopyToast = false
    @State private var toastMessage = ""

    // Splash screen animation state
    @State private var showSplash = !Self.hasLoadedSplash
    @State private var splashDrawn = false
    @State private var splashScale: CGFloat = 1.0
    @State private var opacity: Double = 1.0

    // Single contextual tip — the most relevant TipKit tip, shown one at a time.
    @State private var activeTip: (any Tip)?

    @State private var dismissedFMCTA = false

    public static var hasLoadedSplash = false

    public init() {}

    public var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                // Balanced two-column layout: Voices on the left, Compose on the right.
                HStack(alignment: .top, spacing: 0) {
                    voicesColumn
                    Divider()
                        .overlay(Brand.Surface.divider(for: scheme))
                    composeColumn
                }

                if activeTip != nil {
                    tipStrip
                }

                if !appState.recentGenerations.isEmpty && !appState.isGenerating {
                    recentHistorySection
                        .padding(.horizontal, Brand.Layout.spacingM)
                        .padding(.vertical, Brand.Layout.spacingXS)
                        .transition(
                            reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
                        )
                }

                Divider()
                    .overlay(Brand.Surface.divider(for: scheme))
                    .padding(.horizontal, Brand.Layout.spacingM)

                bottomBar
            }
            .frame(width: 640)
            .background(.ultraThinMaterial)
            .task {
                await evaluateActiveTip()
                FoundationModelsAvailability.shared.refresh()
                appState.hasOpenedMenuBar = true
                syncTipParameters(appState: appState)
                NotificationCenter.default.post(name: .signoffMenuBarAppUsed, object: nil)
            }

            // Copy confirmation toast overlay
            if showCopyToast {
                CopyToastView(message: toastMessage)
                    .transition(
                        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))
                    )
                    .zIndex(1)
            }

            // Reveal splash overlay — a quick brand moment, then out of the way.
            // Writes the signature symbol on, then zooms and fades out — centered
            // over the popover so it reads as a deliberate reveal, not a stray element.
            if showSplash {
                ZStack {
                    Brand.Surface.page(for: scheme)
                        .ignoresSafeArea()

                    Image(systemName: "signature")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(Brand.ember(for: scheme))
                        .symbolEffect(.drawOn.individually, options: .nonRepeating, isActive: splashDrawn)
                        .scaleEffect(splashScale)
                        .opacity(opacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(2)
                .transition(.opacity)
                .onAppear {
                    guard !reduceMotion else {
                        showSplash = false
                        Self.hasLoadedSplash = true
                        return
                    }

                    DispatchQueue.main.async { splashDrawn = true }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        withAnimation(.easeOut(duration: 0.35)) {
                            splashScale = 1.3
                            opacity = 0.0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showSplash = false
                                Self.hasLoadedSplash = true
                            }
                        }
                    }
                }
            }
        }
        .animation(Brand.Motion.safe(.spring(response: 0.35, dampingFraction: 0.8), reduceMotion: reduceMotion), value: showCopyToast)
    }

    // MARK: - Voices (left column)

    private var voicesColumn: some View {
        VStack(alignment: .leading, spacing: Brand.Layout.spacingS) {
            sectionLabel("Voices", systemImage: "square.stack.3d.up.fill")

            if appState.buckets.isEmpty {
                VStack(alignment: .leading, spacing: Brand.Layout.spacingXS) {
                    Text("No voices yet.")
                        .font(Brand.Typography.callout.weight(.medium))
                        .foregroundStyle(Brand.Ink.primary(for: scheme))
                    Text("Open Settings to seed the defaults.")
                        .font(Brand.Typography.caption1)
                        .foregroundStyle(Brand.Ink.tertiary(for: scheme))
                }
                .padding(Brand.Layout.spacingM)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Brand.Layout.radiusM, style: .continuous)
                        .fill(Brand.Surface.card(for: scheme).opacity(scheme.isDark ? 0.5 : 0.6))
                )
            } else {
                VStack(spacing: 6) {
                    ForEach(appState.buckets, id: \.id) { bucket in
                        MenuBucketRow(
                            bucket: bucket,
                            isSelected: bucket.id == appState.selectedBucketId,
                            action: { appState.selectedBucketId = bucket.id }
                        )
                    }
                }
            }
        }
        .frame(width: 224, alignment: .leading)
        .padding(.horizontal, Brand.Layout.spacingM)
        .padding(.vertical, Brand.Layout.spacingM)
    }

    // MARK: - Compose (right column)

    private var composeColumn: some View {
        VStack(alignment: .leading, spacing: Brand.Layout.spacingS) {
            sectionLabel("Compose", systemImage: "square.and.pencil")

            if let bucket = appState.selectedBucket {
                Text(bucket.toneLabel)
                    .font(Brand.Typography.caption1)
                    .foregroundStyle(Brand.accent(for: bucket.id, scheme: scheme))
                    .lineLimit(2)
            }

            // Primary + secondary actions, full-width and obviously interactive.
            // "Generate" previews the signoff first (copy to clipboard, no auto-paste),
            // "Generate & Paste" lands it at the cursor immediately.
            VStack(spacing: Brand.Layout.spacingS) {
                Button {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    Task { await appState.generateNow(shouldAutoPaste: false) }
                } label: {
                    Label("Generate", systemImage: "signature")
                        .font(Brand.Typography.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Brand.ember(for: scheme))
                .disabled(appState.isGenerating || appState.selectedBucket == nil)
                .accessibilityHint("Generate a signoff in the selected voice and copy it to the clipboard.")
                .sensoryFeedback(.impact, trigger: appState.generatedText)

                HStack(spacing: Brand.Layout.spacingS) {
                    Button {
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                        Task { await appState.generateNow(shouldAutoPaste: true) }
                    } label: {
                        Label("Generate & Paste", systemImage: "arrow.right.to.line")
                            .font(Brand.Typography.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(appState.isGenerating || appState.selectedBucket == nil)
                    .accessibilityHint("Generate a signoff and paste it at your cursor.")

                    Button {
                        appState.copyMostRecent()
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                        Task { @MainActor in
                            await SystemSoundClient.shared.play(.tink)
                        }
                    } label: {
                        Label("Copy Last", systemImage: "doc.on.doc")
                            .font(Brand.Typography.callout.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(appState.recentGenerations.isEmpty)
                    .accessibilityHint("Copy the most recent signoff to the clipboard.")
                }
            }

            previewSection
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Brand.Layout.spacingM)
        .padding(.vertical, Brand.Layout.spacingM)
    }

    /// Section label with a leading icon — small caps, tertiary ink.
    private func sectionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(Brand.Ink.tertiary(for: scheme))
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Preview / Status Area

    @ViewBuilder
    private var previewSection: some View {
        if let storeFailure = failureFromStoreRecovery(appState.storeRecovery) {
            ErrorFixCard(
                failure: storeFailure,
                onAction: handleFixAction,
                onDismiss: { appState.storeRecovery = nil }
            )
        } else if let bucket = appState.selectedBucket, bucket.id == BucketID.custom.rawValue {
            customFooterPreview(bucket)
        } else if let txt = appState.generatedText, !appState.isGenerating {
            SignatureCardView(text: txt, providerKind: appState.lastProviderKind)
                .transition(
                    reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
                )
        } else if appState.isGenerating {
            GeneratingDelightView()
                .frame(minHeight: 150)
                .accessibilityLabel("Generating signoff")
        } else if shouldShowFMAvailabilityCard {
            ErrorFixCard(
                failure: .fmUnavailable,
                onAction: handleFixAction,
                onDismiss: { dismissedFMCTA = true }
            )
        } else {
            EmptyDelightView(selectedBucket: appState.selectedBucket)
                .accessibilityLabel("No signoff yet. Press Generate.")
        }
    }

    /// Custom bucket: live preview of the user-authored footer, rendered rich
    /// (formatting + image) exactly as it will paste. No model involved.
    @ViewBuilder
    private func customFooterPreview(_ bucket: Bucket) -> some View {
        if let footer = RichTextFooter.attributed(from: bucket.footerRTFData),
           !footer.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: Brand.Layout.spacingS) {
                AttributedStringPreview(attributed: footer)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Brand.Layout.spacingM)
                    .background(
                        RoundedRectangle(cornerRadius: Brand.Layout.radiusM, style: .continuous)
                            .fill(Brand.Surface.card(for: scheme).opacity(scheme.isDark ? 0.5 : 0.6))
                    )

                Text("Your footer — Generate copies it, Generate & Paste inserts it at your cursor.")
                    .font(Brand.Typography.caption1)
                    .foregroundStyle(Brand.Ink.tertiary(for: scheme))
            }
            .transition(
                reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
            )
        } else {
            VStack(spacing: Brand.Layout.spacingXS) {
                Text("No footer yet")
                    .font(Brand.Typography.headline)
                    .foregroundStyle(Brand.Ink.primary(for: scheme))
                Text("Write one under Settings → Buckets → Custom.")
                    .font(Brand.Typography.callout)
                    .foregroundStyle(Brand.Ink.secondary(for: scheme))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Brand.Layout.spacingM)
            .transition(
                reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
            )
        }
    }

    private var shouldShowFMAvailabilityCard: Bool {
        guard !dismissedFMCTA else { return false }
        let fmAvailability = FoundationModelsAvailability.shared
        switch fmAvailability.status {
        case .appleIntelligenceNotEnabled, .modelNotReady: return true
        default: return false
        }
    }

    // MARK: - Tips (single contextual slot)

    private var tipStrip: some View {
        HStack(spacing: Brand.Layout.spacingS) {
            if let tip = activeTip {
                TipView(tip, arrowEdge: .top)
                    .tipBackground(Brand.Surface.card(for: scheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Brand.Layout.spacingM)
        .padding(.vertical, Brand.Layout.spacingS)
        .transition(
            reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
        )
    }

    /// Pick the single most relevant tip: iterate in priority order and keep the
    /// first that TipKit reports as `.available`. Runs once per popover open.
    private func evaluateActiveTip() async {
        guard activeTip == nil else { return }
        let candidates: [any Tip] = [
            SelectBucketTip.selectBucketTip,
            GenerateNeedsBucketTip.generateNeedsBucketTip,
            FirstGenerationTip.firstGenerationTip,
            AccessibilityPermissionTip.accessibilityPermissionTip,
            InputMonitoringPermissionTip.inputMonitoringPermissionTip,
            TeachVoiceTip.teachVoiceTip,
            CustomBucketTip.customBucketTip,
        ]
        for tip in candidates {
            for await status in tip.statusUpdates {
                if status == .available {
                    activeTip = tip
                }
                break
            }
            if activeTip != nil { return }
        }
    }

    // MARK: - Bottom Bar (status + Settings/Quit)

    private var bottomBar: some View {
        HStack(spacing: Brand.Layout.spacingS) {
            Spacer(minLength: 0)

            Button {
                NotificationCenter.default.post(name: .openSettingsShortcutTriggered, object: nil)
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .help("Settings")
            .accessibilityLabel("Settings")
            .accessibilityHint("Open Signoff settings. Shortcut Control-Command-comma.")

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .help("Quit Signoff")
            .accessibilityLabel("Quit Signoff")
            .accessibilityHint("Quit Signoff. Shortcut Command-Q while Settings is open.")
        }
        .padding(.horizontal, Brand.Layout.spacingM)
        .padding(.vertical, Brand.Layout.spacingS)
    }

    // MARK: - Actions

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

    /// Show a toast notification for copy/share actions
    private func showToast(_ message: String) {
        toastMessage = message
        // HIG accessibility: announce transient feedback to assistive tech.
        if let window = viewForAccessibility() {
            NSAccessibility.post(element: window,
                                 notification: .announcementRequested,
                                 userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: message])
        }
        withAnimation(Brand.Motion.safe(.spring(response: 0.3, dampingFraction: 0.7), reduceMotion: reduceMotion)) {
            showCopyToast = true
        }
        // Auto-dismiss after 1.5s
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(Brand.Motion.safe(.easeOut(duration: 0.2), reduceMotion: reduceMotion)) {
                showCopyToast = false
            }
        }
    }
    /// Best-effort accessibility element for announcement. Uses the key window;
    /// in a menu bar popover this is the SwiftUI hosting window for the content.
    private func viewForAccessibility() -> AnyObject? {
        NSApp.keyWindow ?? NSApp.windows.first
    }
}

/// Bucket row for menu content — glassy hover fill, ember selection, shortcut badge.
@MainActor
private struct MenuBucketRow: View {
    let bucket: Bucket
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var accent: Color { Brand.accent(for: bucket.id, scheme: scheme) }
    private var iconColor: Color { isSelected ? Brand.ember(for: scheme) : accent }
    private var nameFont: Font { Brand.Typography.callout.weight(.semibold) }
    private var toneFont: Font { Brand.Typography.caption2 }
    private var primaryInk: Color { Brand.Ink.primary(for: scheme) }
    private var tertiaryInk: Color { Brand.Ink.tertiary(for: scheme) }
    private var emColor: Color { Brand.ember(for: scheme) }
    private var cardSurface: Color { Brand.Surface.card(for: scheme) }
    private var dividerColor: Color { Brand.Surface.divider(for: scheme) }
    private var hairline: CGFloat { Brand.Layout.hairline }
    private var radiusM: CGFloat { Brand.Layout.radiusM }
    private var spacingM: CGFloat { Brand.Layout.spacingM }
    private var spacingXS: CGFloat { Brand.Layout.spacingXS }

    /// Inline keyboard shortcut
    private var shortcutText: String? {
        let manager = ShortcutManager.shared
        let bindings = manager.decode(AppState.shared.settings.bucketShortcutsJSON)
        if let binding = bindings.first(where: { $0.bucketId == bucket.id }) {
            let mod = binding.modifier == "optCmd" ? "⌥⌘" : "⌃⌘"
            return "\(mod)\(binding.digitKey)"
        }
        return nil
    }

    var body: some View {
        Button(action: {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            action()
        }) {
            HStack(spacing: spacingM) {
                Image(systemName: bucket.iconSymbol)
                    .font(.body.weight(.medium))
                    .frame(width: 20)
                    .foregroundStyle(iconColor)
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading, spacing: 2) {
                    Text(bucket.name)
                        .font(nameFont)
                        .foregroundStyle(primaryInk)
                        .lineLimit(1)
                    Text(bucket.toneLabel)
                        .font(toneFont)
                        .foregroundStyle(tertiaryInk)
                        .textCase(.lowercase)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // Inline keyboard shortcut hint
                if let shortcut = shortcutText {
                    Text(shortcut)
                        .font(Brand.Typography.mono)
                        .foregroundStyle(tertiaryInk.opacity(isSelected ? 0.7 : 0.4))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(cardSurface.opacity(0.5))
                        )
                        .transition(
                            reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing))
                        )
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(emColor)
                        .accessibilityHidden(true)
                        .transition(
                            reduceMotion ? .opacity : .scale.combined(with: .opacity)
                        )
                }
            }
            .padding(.horizontal, spacingM)
            .padding(.vertical, Brand.Layout.spacingS)
            .background(
                RoundedRectangle(cornerRadius: radiusM, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radiusM, style: .continuous)
                    .stroke(isSelected ? emColor.opacity(0.35) : .clear,
                            lineWidth: hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(shortcutHintForBucket(bucket.id))
        .onHover { h in isHovered = h }
        .animation(hoverAnimation, value: isHovered)
        .animation(selectAnimation, value: isSelected)
        .accessibilityLabel("\(bucket.name) bucket")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(bucket.toneLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var backgroundFill: Color {
        if isSelected {
            return cardSurface.opacity(0.7)
        }
        if isHovered {
            return cardSurface.opacity(0.45)
        }
        return .clear
    }

    private var hoverAnimation: Animation {
        Brand.Motion.safe(.easeOut(duration: 0.15), reduceMotion: reduceMotion)
    }

    private var selectAnimation: Animation {
        Brand.Motion.safe(.spring(response: 0.3, dampingFraction: 0.7), reduceMotion: reduceMotion)
    }

    private func shortcutHintForBucket(_ id: String) -> String {
        let manager = ShortcutManager.shared
        let bindings = manager.decode(AppState.shared.settings.bucketShortcutsJSON)
        if let binding = bindings.first(where: { $0.bucketId == id }) {
            let mod = binding.modifier == "optCmd" ? "⌥⌘" : "⌃⌘"
            return "Shortcut: \(mod)\(binding.digitKey) — Click to select, then Generate"
        }
        return "Click to select, then press Generate"
    }
}

// MARK: - State Views

/// Minimal indeterminate progress while a signoff is being generated.
private struct GeneratingDelightView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Brand.Layout.spacingS) {
            Image(systemName: "signature")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Brand.ember(for: scheme))
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)

            Text("Generating…")
                .font(Brand.Typography.callout)
                .foregroundStyle(Brand.Ink.secondary(for: scheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Compact empty state — sized for the compose column.
@MainActor
private struct EmptyDelightView: View {
    let selectedBucket: Bucket?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: Brand.Layout.spacingM) {
            ZStack {
                Circle()
                    .fill(bucketColor.opacity(0.15))
                    .frame(width: 56, height: 56)

                Image(systemName: bucketIcon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(bucketColor)
            }

            VStack(spacing: Brand.Layout.spacingXS) {
                Text("No signoff yet")
                    .font(Brand.Typography.headline)
                    .foregroundStyle(Brand.Ink.primary(for: scheme))
                    .multilineTextAlignment(.center)

                Text("Press Generate to draft one.")
                    .font(Brand.Typography.callout)
                    .foregroundStyle(Brand.Ink.secondary(for: scheme))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Brand.Layout.spacingM)
    }

    private var bucketIcon: String {
        selectedBucket?.iconSymbol ?? "signature"
    }

    private var bucketColor: Color {
        guard let bucket = selectedBucket else { return Brand.ember(for: scheme) }
        return Brand.accent(for: bucket.id, scheme: scheme)
    }
}

// MARK: - Recent History Carousel

/// Horizontal swipeable carousel of recent signoffs
@MainActor
private struct RecentHistorySection: View {
    let generations: [SignoffGeneration]
    let onSelect: (SignoffGeneration) -> Void
    let onShare: (SignoffGeneration) -> Void
    let onCopy: (SignoffGeneration) -> Void
    let onThumbsUp: (SignoffGeneration) -> Void
    let onThumbsDown: (SignoffGeneration) -> Void
    let onTrash: (SignoffGeneration) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let visibleCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Layout.spacingS) {
            HStack {
                Text("Recent")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(Brand.Ink.tertiary(for: scheme))
                Spacer()
                if generations.count > visibleCount {
                    Text("\(generations.count) total")
                        .font(Brand.Typography.caption2)
                        .foregroundStyle(Brand.Ink.tertiary(for: scheme))
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Brand.Layout.spacingS) {
                    ForEach(Array(generations.prefix(10).enumerated()), id: \.element.id) { index, gen in
                        RecentSignoffCard(
                            generation: gen,
                            isFirst: index == 0,
                            action: { onSelect(gen) },
                            shareAction: { onShare(gen) },
                            copyAction: { onCopy(gen) },
                            thumbsUpAction: { onThumbsUp(gen) },
                            thumbsDownAction: { onThumbsDown(gen) },
                            trashAction: { onTrash(gen) }
                        )
                        .staggeredEntrance(index: index, reduceMotion: reduceMotion)
                    }
                }
                .padding(.horizontal, Brand.Layout.spacingXS)
            }
            .scrollTargetLayout()
            .frame(height: 128)
        }
    }
}

/// Individual recent signoff card — glassy surface.
@MainActor
private struct RecentSignoffCard: View {
    let generation: SignoffGeneration
    let isFirst: Bool
    let action: () -> Void
    let shareAction: () -> Void
    let copyAction: () -> Void
    let thumbsUpAction: () -> Void
    let thumbsDownAction: () -> Void
    let trashAction: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var bucketAccent: Color {
        Brand.accent(for: generation.bucketId, scheme: scheme)
    }

    /// Internal IDs (standard/unhinged) display as their public names
    /// (Normal/Cynical).
    private var displayBucketName: String {
        switch generation.bucketId {
        case BucketID.standard.rawValue: "Normal"
        case BucketID.unhinged.rawValue: "Cynical"
        default: generation.bucketId.capitalized
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Layout.spacingXS) {
            // Bucket indicator dot
            HStack {
                Circle()
                    .fill(bucketAccent)
                    .frame(width: 6, height: 6)
                Text(displayBucketName)
                    .font(Brand.Typography.caption2.weight(.medium))
                    .foregroundStyle(Brand.Ink.tertiary(for: scheme))
                Spacer()
                Text(generation.createdAt, style: .relative)
                    .font(Brand.Typography.caption2)
                    .foregroundStyle(Brand.Ink.tertiary(for: scheme).opacity(0.6))
            }

            // Signoff text preview — the whole text is the primary "use this" action.
            Button(action: action) {
                Text(generation.text)
                    .font(Brand.Typography.signoff)
                    .foregroundStyle(Brand.Ink.primary(for: scheme))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isFirst)
            .help(isFirst ? "Current signoff" : "Use this signoff")
            .accessibilityLabel(isFirst ? "Current signoff" : "Use this signoff")

            // Action buttons
            HStack(spacing: Brand.Layout.spacingXS) {
                Button(action: copyAction) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption.weight(.medium))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(GlassButtonStyle(scheme: scheme, accent: bucketAccent))
                .help("Copy to clipboard")
                .accessibilityLabel("Copy to clipboard")

                Button(action: shareAction) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption.weight(.medium))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(GlassButtonStyle(scheme: scheme, accent: bucketAccent))
                .help("Share as image")
                .accessibilityLabel("Share as image")

                Button(action: thumbsUpAction) {
                    Image(systemName: generation.isFavorite ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.caption.weight(.medium))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(GlassButtonStyle(scheme: scheme, accent: generation.isFavorite ? .green : bucketAccent))
                .help(generation.isFavorite ? "Favorited — tap to unmark" : "Thumbs up — teach your voice")
                .accessibilityLabel(generation.isFavorite ? "Favorited. Remove favorite." : "Thumbs up")

                Button(action: thumbsDownAction) {
                    Image(systemName: "hand.thumbsdown")
                        .font(.caption.weight(.medium))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(GlassButtonStyle(scheme: scheme, accent: bucketAccent))
                .help("Thumbs down — teach your voice what to avoid")
                .accessibilityLabel("Thumbs down")

                Button(action: trashAction) {
                    Image(systemName: "trash")
                        .font(.caption.weight(.medium))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(GlassButtonStyle(scheme: scheme, accent: bucketAccent))
                .help("Delete from history")
                .accessibilityLabel("Delete from history")
            }
        }
        .padding(Brand.Layout.spacingS)
        .frame(width: 250, height: 118)
        .background(
            RoundedRectangle(cornerRadius: Brand.Layout.radiusM, style: .continuous)
                .fill(Brand.Surface.card(for: scheme).opacity(scheme.isDark ? 0.5 : 0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.Layout.radiusM, style: .continuous)
                        .stroke(
                            isHovered ? bucketAccent.opacity(0.35) : Brand.Surface.divider(for: scheme),
                            lineWidth: isHovered ? Brand.Layout.borderWeight : Brand.Layout.hairline
                        )
                )
        )
        .contentShape(Rectangle())
        .onHover { h in
            withAnimation(Brand.Motion.safe(.easeOut(duration: 0.15), reduceMotion: reduceMotion)) {
                isHovered = h
            }
        }
    }
}

/// Glass-style button for history cards
private struct GlassButtonStyle: ButtonStyle {
    let scheme: ColorScheme
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(scheme == .dark ? .white : .black)
            .background(
                Circle()
                    .fill(accent.opacity(configuration.isPressed ? 0.3 : 0.15))
                    .overlay(
                        Circle()
                            .stroke(Brand.Surface.divider(for: scheme), lineWidth: Brand.Layout.hairline)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Shareable Card

/// Generates a beautiful shareable image of the signoff
@MainActor
private struct ShareableSignoffCard: View {
    let text: String
    let bucketId: String
    let providerKind: GenerationProviderKind?
    let userName: String?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            // Parchment background with subtle texture
            RoundedRectangle(cornerRadius: Brand.Layout.radiusL, style: .continuous)
                .fill(Brand.Surface.page(for: scheme))

            // Subtle ink wash edge
            RoundedRectangle(cornerRadius: Brand.Layout.radiusL, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Brand.accent(for: bucketId, scheme: scheme).opacity(0.4),
                            Brand.accent(for: bucketId, scheme: scheme).opacity(0.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )

            VStack(alignment: .leading, spacing: Brand.Layout.spacingL) {
                // Header with bucket personality
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Signoff", systemImage: "signature")
                            .font(Brand.Typography.caption1.weight(.semibold))
                            .foregroundStyle(Brand.Ink.secondary(for: scheme))
                        Text(bucketTagline)
                            .font(Brand.Typography.caption2)
                            .foregroundStyle(Brand.Ink.tertiary(for: scheme))
                    }
                    Spacer()
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Brand.accent(for: bucketId, scheme: scheme).opacity(0.6))
                }

                // The signoff text — beautifully typeset
                Text(text)
                    .font(Brand.Typography.signoff)
                    .foregroundStyle(Brand.Ink.primary(for: scheme))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineSpacing(4)

                // Footer
                HStack {
                    if let userName {
                        Text("— \(userName)")
                            .font(Brand.Typography.footnote.italic())
                            .foregroundStyle(Brand.Ink.secondary(for: scheme))
                    }
                    Spacer()
                    // Watermark
                    HStack(spacing: 4) {
                        Image(systemName: "signature")
                            .font(.caption2)
                        Text("Signoff")
                            .font(Brand.Typography.caption2.weight(.medium))
                    }
                    .foregroundStyle(Brand.Ink.tertiary(for: scheme).opacity(0.5))
                }
            }
            .padding(Brand.Layout.spacingXL)
        }
        .frame(width: 520, height: 320)
    }

    private var bucketTagline: String {
        switch bucketId {
        case BucketID.standard.rawValue: "Normal voice"
        case BucketID.professional.rawValue: "Professional voice"
        case BucketID.unhinged.rawValue: "Cynical voice"
        case BucketID.custom.rawValue: "Custom voice"
        default: "Generated with Signoff"
        }
    }
}

// MARK: - Copy Toast

/// Delightful toast confirmation for copy/share actions
@MainActor
private struct CopyToastView: View {
    let message: String

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: Brand.Layout.spacingS) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(Brand.Typography.callout.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, Brand.Layout.spacingL)
            .padding(.vertical, Brand.Layout.spacingM)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.85))
                    .shadow(
                        color: Color.black.opacity(0.2),
                        radius: 12, x: 0, y: 6
                    )
            )
            .padding(.bottom, 80) // Above menu bar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

private extension SignoffMenuContent {
    /// Insert the recent history section into the view hierarchy
    var recentHistorySection: some View {
        RecentHistorySection(
            generations: appState.recentGenerations,
            onSelect: { gen in
                appState.generatedText = gen.text
                showToast("Loaded \"\(gen.text.prefix(30))…\"")
            },
            onShare: { gen in
                shareSignoff(gen)
            },
            onCopy: { gen in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(gen.text, forType: .string)
                Task { @MainActor in
                    await SystemSoundClient.shared.play(.tink)
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                }
                showToast("Copied \"\(gen.text.prefix(30))…\"")
            },
            onThumbsUp: { gen in
                appState.applyFeedback(gen, liked: true)
                showToast("Liked — I'll write more like this.")
            },
            onThumbsDown: { gen in
                appState.applyFeedback(gen, liked: false)
                showToast("Noted — I'll avoid this style.")
            },
            onTrash: { gen in
                appState.deleteGeneration(gen)
                showToast("Removed from history.")
            }
        )
    }

    /// Export signoff as shareable image
    private func shareSignoff(_ generation: SignoffGeneration) {
        let card = ShareableSignoffCard(
            text: generation.text,
            bucketId: generation.bucketId,
            providerKind: GenerationProviderKind(rawValue: generation.providerRaw),
            userName: appState.profile.name.isEmpty ? nil : appState.profile.name
        )

        let renderer = ImageRenderer(content: card)
        renderer.scale = 2.0 // Retina
        if let nsImage = renderer.nsImage {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([nsImage])

            Task { @MainActor in
                await SystemSoundClient.shared.play(.pop)
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
            showToast("Signoff copied as image")
        }
    }
}

