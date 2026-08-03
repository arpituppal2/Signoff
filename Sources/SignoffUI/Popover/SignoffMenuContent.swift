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
    @State private var splashFadeOut = false
    @State private var splashScale: CGFloat = 1.0
    @State private var opacity: Double = 1.0

    // Single contextual tip — the most relevant TipKit tip, shown one at a time.
    @State private var activeTip: (any Tip)?

    @State private var dismissedFMCTA = false

    /// Toggles the history page; set via the clock icon button in the bottom bar.
    @State private var showHistory = false

    public static var hasLoadedSplash = false

    public init() {}

    public var body: some View {
        ZStack {
            if showHistory {
                HistoryPageView(onBack: { showHistory = false })
                    .frame(width: 580)
                    .frame(minHeight: 480)
                    .background(popoverGlass)
            } else {
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

                Divider()
                    .overlay(Brand.Surface.divider(for: scheme))
                    .padding(.horizontal, Brand.Layout.spacingM)

                bottomBar
            }
            // Use slightly narrower width so the popover centers cleanly under the
            // menu bar item; 640 was pushing left on smaller screens.
            .frame(minWidth: 520, idealWidth: 580, maxWidth: 700)
            .background(popoverGlass)
            .task {
                await evaluateActiveTip()
                FoundationModelsAvailability.shared.refresh()
                appState.hasOpenedMenuBar = true
                syncTipParameters(appState: appState)
                NotificationCenter.default.post(name: .signoffMenuBarAppUsed, object: nil)
            }

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
            // Writes the signature symbol on, then zooms way out (scale 4x) and
            // fades so it vanishes off-screen, then the popover reveals.
            if showSplash {
                ZStack {
                    popoverGlass.ignoresSafeArea()

                    Image(systemName: "signature")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(Brand.ember(for: scheme))
                        .symbolEffect(.drawOn.individually, options: .nonRepeating, isActive: splashDrawn)
                        .symbolEffect(.drawOff.individually, options: .nonRepeating, isActive: splashFadeOut)
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

                    // Phase 1: drawOn (0.5s)
                    DispatchQueue.main.async { splashDrawn = true }

                    // Phase 2: zoom to 5x over 0.1s while also drawing off
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        splashFadeOut = true
                        withAnimation(.easeOut(duration: 0.1)) {
                            splashScale = 5.0
                        }
                    }

                    // Phase 3: fade out 0.15s
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            opacity = 0.0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            showSplash = false
                            Self.hasLoadedSplash = true
                        }
                    }
                }
            }
        }
        .animation(Brand.Motion.safe(.spring(response: 0.35, dampingFraction: 0.8), reduceMotion: reduceMotion), value: showCopyToast)
    }

    /// Frosted glass popover background — .regularMaterial (70 % opaque) with a
    /// whisper of the selected bucket's accent colour so the popover reads as
    /// glassy but not washed out. The menu bar extra uses .window style so this
    /// material sits behind the entire surface.
    private var popoverGlass: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).opacity(0.35)
            selectedBucketTint.opacity(0.06)
        }
        .background(.regularMaterial)
    }

    /// The selected bucket's accent, or the brand neutral if nothing is selected.
    private var selectedBucketTint: Color {
        guard let bucket = appState.selectedBucket else { return Brand.ember(for: scheme) }
        return Brand.accent(for: bucket.id, scheme: scheme)
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
            SignatureCardView(text: txt)
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
                showHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .help("History")
            .accessibilityLabel("History")
            .accessibilityHint("View your recent signoffs.")

            Button {
                // Close the popover first (it is open here) before revealing
                // Settings, so the user isn't left with the popover floating
                // over the Settings window. Closing-then-opening avoids the
                // race where the Settings window would auto-dismiss the popover
                // and a follow-up toggle would reopen it. `.toggleMenuBarPopover`
                // routes through the app delegate, which owns MenuBarExtra control.
                NotificationCenter.default.post(name: .toggleMenuBarPopover, object: nil)
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

    /// The bucket icon with a subtle selection animation.
    private var bucketIcon: some View {
        let base = Image(systemName: bucket.iconSymbol)
            .font(.body.weight(.medium))
            .frame(width: 20)
            .foregroundStyle(iconColor)
            .symbolRenderingMode(.hierarchical)

        if reduceMotion {
            return AnyView(base)
        }
        return AnyView(base
            .symbolEffect(.bounce, value: isSelected)
            .symbolEffect(.pulse, value: isSelected)
        )
    }

    /// Inline keyboard shortcut — always display as ⌃⌘ (cmdCtrl) per design.
    private var shortcutText: String? {
        let manager = ShortcutManager.shared
        let bindings = manager.decode(AppState.shared.settings.bucketShortcutsJSON)
        if let binding = bindings.first(where: { $0.bucketId == bucket.id }) {
            return "⌃⌘\(binding.digitKey)"
        }
        return nil
    }

    var body: some View {
        Button(action: {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            withAnimation(Brand.Motion.safe(.spring(response: 0.3, dampingFraction: 0.7), reduceMotion: reduceMotion)) {
                action()
            }
        }) {
            HStack(spacing: spacingM) {
                bucketIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(bucket.name)
                        .font(nameFont)
                        .foregroundStyle(primaryInk)
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
        .onHover { h in
            withAnimation(Brand.Motion.safe(.easeOut(duration: 0.15), reduceMotion: reduceMotion)) {
                isHovered = h
            }
        }
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
            // Parchment background — the "Ink on Paper" page.
            RoundedRectangle(cornerRadius: Brand.Layout.radiusL, style: .continuous)
                .fill(Brand.Surface.page(for: scheme))

            // Single amber hairline border — restrained, brand-coded.
            RoundedRectangle(cornerRadius: Brand.Layout.radiusL, style: .continuous)
                .stroke(Brand.ember(for: scheme).opacity(0.35), lineWidth: Brand.Layout.borderWeight)

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
                    // Brand mark — the signature glyph in the bucket's tonal ink.
                    Image(systemName: "signature")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Brand.accent(for: bucketId, scheme: scheme).opacity(0.7))
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

// MARK: - History Page

/// Full-page signed-off history — replaces the bottom carousel. Accessed via the
/// clock icon button in the menu bar popover's bottom bar. Same 640 pt width as
/// the main popover surface, with a back button to return.
@MainActor
private struct HistoryPageView: View {
    let onBack: () -> Void
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var toastMessage = ""
    @State private var showToast = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with back button
            HStack {
                Button {
                    onBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Back to main view")

                Spacer()

                Text("History")
                    .font(.headline)
                    .foregroundStyle(Brand.Ink.primary(for: scheme))
            }
            .padding(.horizontal, Brand.Layout.spacingM)
            .padding(.vertical, Brand.Layout.spacingS)

            Divider()
                .overlay(Brand.Surface.divider(for: scheme))

            if appState.recentGenerations.isEmpty {
                emptyHistory
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Brand.Layout.spacingS) {
                        ForEach(appState.recentGenerations) { gen in
                            HistoryRow(
                                generation: gen,
                                onCopy: { copyGen(gen) },
                                onThumbsUp: { appState.applyFeedback(gen, liked: true) },
                                onThumbsDown: { appState.applyFeedback(gen, liked: false) },
                                onTrash: { appState.deleteGeneration(gen) },
                                onSelect: { appState.generatedText = gen.text }
                            )
                        }
                    }
                    .padding(Brand.Layout.spacingM)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showToast {
                CopyToastView(message: toastMessage)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: showToast)
    }

    private var emptyHistory: some View {
        VStack(spacing: Brand.Layout.spacingM) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Brand.Ink.tertiary(for: scheme))
            Text("No History Yet")
                .font(Brand.Typography.headline)
                .foregroundStyle(Brand.Ink.primary(for: scheme))
            Text("Generated signoffs will appear here.")
                .font(Brand.Typography.callout)
                .foregroundStyle(Brand.Ink.secondary(for: scheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copyGen(_ gen: SignoffGeneration) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(gen.text, forType: .string)
        Task { @MainActor in
            await SystemSoundClient.shared.play(.tink)
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        flashToast("Copied")
    }

    private func flashToast(_ msg: String) {
        toastMessage = msg
        withAnimation(.easeOut(duration: 0.15)) { showToast = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeOut(duration: 0.15)) { showToast = false }
        }
    }
}

/// A single history-row — signoff text, bucket badge, timestamp, and a compact
/// action bar (copy, thumbs, trash). No share button.
@MainActor
private struct HistoryRow: View {
    let generation: SignoffGeneration
    let onCopy: () -> Void
    let onThumbsUp: () -> Void
    let onThumbsDown: () -> Void
    let onTrash: () -> Void
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var isHovered = false

    private var bucketAccent: Color {
        Brand.accent(for: generation.bucketId, scheme: scheme)
    }

    private var displayBucketName: String {
        switch generation.bucketId {
        case BucketID.standard.rawValue: "Normal"
        case BucketID.unhinged.rawValue:  "Cynical"
        default: generation.bucketId.capitalized
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Layout.spacingXS) {
            // Header: bucket chip + timestamp
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

            // Signoff text
            Button(action: onSelect) {
                Text(generation.text)
                    .font(Brand.Typography.signoff)
                    .foregroundStyle(Brand.Ink.primary(for: scheme))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to set as current signoff")

            // Action bar — copy, thumbs up/down, trash. No share.
            HStack(spacing: Brand.Layout.spacingXS) {
                SmallIconButton(symbol: "doc.on.doc", action: onCopy, help: "Copy")
                SmallIconButton(
                    symbol: generation.isFavorite ? "hand.thumbsup.fill" : "hand.thumbsup",
                    tint: generation.isFavorite ? .green : nil,
                    action: onThumbsUp,
                    help: generation.isFavorite ? "Favorited" : "Thumbs up"
                )
                SmallIconButton(symbol: "hand.thumbsdown", action: onThumbsDown, help: "Thumbs down")
                SmallIconButton(symbol: "trash", action: onTrash, help: "Delete")
            }
        }
        .padding(Brand.Layout.spacingS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Brand.Layout.radiusS, style: .continuous)
                .fill(Brand.Surface.card(for: scheme).opacity(scheme.isDark ? 0.5 : 0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Brand.Layout.radiusS, style: .continuous)
                .stroke(
                    isHovered ? bucketAccent.opacity(0.25) : Brand.Surface.divider(for: scheme),
                    lineWidth: Brand.Layout.hairline
                )
        )
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = h }
        }
    }
}

/// Tiny 28×28pt icon button — used in the history row action bar.
@MainActor
private struct SmallIconButton: View {
    let symbol: String
    var tint: Color? = nil
    let action: () -> Void
    let help: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.medium))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}

