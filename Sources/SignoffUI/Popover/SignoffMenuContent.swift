import SwiftUI
import SignoffCore
import AppKit

/// Menu content for MenuBarExtra — the primary, always-available surface.
///
/// Layout philosophy: a calm, two-column surface that reads like a small Apple
/// app, not a density demo. Left = Voices (the chooser), Right = Compose (the
/// action + result). A slim status footer beneath carries privacy, provider,
/// and the History/Settings/Quit affordances — so the two main columns are
/// reserved for *content* and never have to fight chrome for attention.
///
/// Hierarchy: Generate & Paste is the single primary action (people open the
/// popover to *land* a signoff, not to preview). Generate is secondary (same
/// output, copy-only — no paste). Tertiary: recopy, history, settings, quit.
///
/// Keyboard-first: the popover inherits the app's command menu; bucket selection
/// and Generate stay one-tap, and the global ⌃⌥N chords work from anywhere.
@MainActor
public struct SignoffMenuContent: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    // Toast state for copy confirmation
    @State private var showCopyToast = false
    @State private var toastMessage = ""

    // Splash screen animation state
    @State private var showSplash = !Self.hasLoadedSplash

    @State private var dismissedFMCTA = false

    /// Toggles the history page; set via the clock icon button in the footer.
    @State private var showHistory = false

    public static var hasLoadedSplash = false

    public init() {}

    public var body: some View {
        ZStack {
            if showHistory {
                HistoryPageView(onBack: { showHistory = false })
                    .background(popoverGlass)
            } else {
                mainSurface
            }

            // Copy confirmation toast overlay — sits above the footer capsule.
            if showCopyToast {
                CopyToastView(message: toastMessage)
                    .transition(
                        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))
                    )
                    .zIndex(1)
            }

            if showSplash {
                SplashOverlay(showSplash: $showSplash)
            }
        }
        .animation(Brand.Motion.safe(.spring(response: 0.35, dampingFraction: 0.8), reduceMotion: reduceMotion), value: showCopyToast)
    }

    /// The two-column main surface. History/Settings/Quit live tucked under
    /// the voices in the left column (they're voice-adjacent utilities), so
    /// there's no full-width chrome bar fighting the content for attention.
    private var mainSurface: some View {
        HStack(alignment: .top, spacing: 0) {
            voicesColumn
            Divider()
                .overlay(Brand.Surface.divider(for: scheme))
            composeColumn
        }
        .padding(Brand.Layout.spacingL)
        .frame(minWidth: 460, idealWidth: 500, maxWidth: 620, minHeight: 294, idealHeight: 322)
        .background(popoverGlass)
        .task {
            FoundationModelsAvailability.shared.refresh()
            appState.hasOpenedMenuBar = true
            NotificationCenter.default.post(name: .signoffMenuBarAppUsed, object: nil)
        }
        // Onboarding trigger: observe the showOnboarding flag (set by
        // AppState.initialize) and the "Re-run onboarding" button in Settings.
        .onChange(of: appState.showOnboarding) { _, shouldShow in
            if shouldShow { openWindow(id: "signoff.onboarding") }
        }
        .onReceive(NotificationCenter.default.publisher(for: .signoffOnboardingRequested)) { _ in
            if appState.showOnboarding { openWindow(id: "signoff.onboarding") }
        }
    }

    // Frosted glass popover background — .regularMaterial (70 % opaque) with a
    /// whisper of the selected bucket's accent colour so the popover reads as
    /// glassy but not washed out. The menu bar extra uses .window style so this
    /// material sits behind the entire surface.
    private var popoverGlass: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).opacity(0.35)
            selectedBucketTint.opacity(0.06)
        }
        .background(.regularMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: Brand.Layout.radiusM, style: .continuous)
                .stroke(Brand.Surface.divider(for: scheme), lineWidth: Brand.Layout.borderWeight)
        )
    }

    /// The selected bucket's accent, or the brand neutral if nothing is selected.
    private var selectedBucketTint: Color {
        guard let bucket = appState.selectedBucket else { return Brand.ember(for: scheme) }
        return Brand.accent(for: bucket.id, scheme: scheme)
    }

    // MARK: - Voices (left column)

    private var voicesColumn: some View {
        VStack(alignment: .leading, spacing: Brand.Layout.spacingS) {
            sectionLabel("Voices", systemImage: "person.2.crop.square.stack.fill")

            if appState.buckets.isEmpty {
                emptyVoicesState
            } else {
                VStack(spacing: 6) {
                    ForEach(appState.buckets, id: \.id) { bucket in
                        MenuBucketRow(
                            bucket: bucket,
                            isSelected: bucket.id == appState.selectedBucketId,
                            showShortcutHint: appState.settings.showShortcutHints,
                            action: { appState.selectedBucketId = bucket.id }
                        )
                    }
                }
            }

            Spacer(minLength: Brand.Layout.spacingM)

            footerRow
        }
        .frame(width: 224, alignment: .leading)
        .padding(.horizontal, Brand.Layout.spacingM)
        .padding(.vertical, Brand.Layout.spacingM)
    }

    private var emptyVoicesState: some View {
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
    }

    // MARK: - Compose (right column)

    private var composeColumn: some View {
        VStack(alignment: .leading, spacing: Brand.Layout.spacingS) {
            sectionLabel("Compose", systemImage: "square.and.pencil")

            // Action pair: "Generate & Paste" is the primary (the thing people
            // open the popover to do); "Generate" is the secondary, paste-free
            // variant whose only difference is no ⌘V at the cursor. Putting the
            // paste action first matches the dominant intent and removes the
            // "which one do I press" hesitation the old equal-weight pair caused.
            VStack(spacing: Brand.Layout.spacingXS) {
                Button {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    Task { await appState.generateNow(shouldAutoPaste: true) }
                } label: {
                    Label("Generate & Paste", systemImage: "arrow.right.to.line")
                        .font(Brand.Typography.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Brand.ember(for: scheme))
                .disabled(appState.isGenerating || appState.selectedBucket == nil)
                .accessibilityHint("Generate a signoff and paste it at your cursor.")
                .sensoryFeedback(.impact, trigger: appState.generatedText)

                Button {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    Task { await appState.generateNow(shouldAutoPaste: false) }
                } label: {
                    Label("Generate", systemImage: "signature")
                        .font(Brand.Typography.callout.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(appState.isGenerating || appState.selectedBucket == nil)
                .accessibilityHint("Generate a signoff and copy it to the clipboard. Press ⌘V yourself to paste.")
            }

            previewSection
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Brand.Layout.spacingM)
        .padding(.vertical, Brand.Layout.spacingM)
    }

    /// Section label — small caps, tertiary ink, with a leading icon.
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

    private var shouldShowFMAvailabilityCard: Bool {
        guard !dismissedFMCTA else { return false }
        let fmAvailability = FoundationModelsAvailability.shared
        switch fmAvailability.status {
        case .appleIntelligenceNotEnabled, .modelNotReady: return true
        default: return false
        }
    }

    // MARK: - Footer row (provider badge + History / Settings / Quit)
    ///
    /// Compact utility row sitting under the voices in the left column — next
    /// to the thing it acts on, not stretched across the whole popover. The
    /// provider badge sits at the leading edge; History/Settings/Quit trail it.
    private var footerRow: some View {
        VStack(spacing: Brand.Layout.spacingS) {
            Divider()
                .overlay(Brand.Surface.divider(for: scheme))

            HStack(spacing: Brand.Layout.spacingXS) {
                if let provider = appState.lastProviderKind {
                    Label(provider.badgeTitle, systemImage: provider.badgeSystemImage)
                        .font(Brand.Typography.caption2.weight(.medium))
                        .foregroundStyle(Brand.Ink.tertiary(for: scheme))
                        .help("Generated by \(provider.badgeTitle)")
                }

                Spacer(minLength: 0)

                footerButton("History", systemImage: "clock.arrow.circlepath") {
                    showHistory = true
                }
                footerButton("Settings", systemImage: "gearshape") {
                    // Close the popover first so Settings isn't hidden under it.
                    NotificationCenter.default.post(name: .toggleMenuBarPopover, object: nil)
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                footerButton("Quit", systemImage: "power", role: .destructive) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    @ViewBuilder
    private func footerButton(_ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
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
        if let window = viewForAccessibility() {
            NSAccessibility.post(element: window,
                                 notification: .announcementRequested,
                                 userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: message])
        }
        withAnimation(Brand.Motion.safe(.spring(response: 0.3, dampingFraction: 0.7), reduceMotion: reduceMotion)) {
            showCopyToast = true
        }
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

// MARK: - Splash

/// Reveal splash overlay — a quick brand moment with write/unwrite animation.
/// Phase 1: drawOn (0.55s) → Phase 2: hold (0.15s) → Phase 3: drawOff (0.45s) → Phase 4: fade (0.2s)
/// Total ~1.35s. Background is fully opaque to prevent the EmptyDelightView signature
/// from showing through next to the splash glyph.
private struct SplashOverlay: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showSplash: Bool

    @State private var drawOnActive = true
    @State private var drawOffActive = false
    @State private var splashOpacity: Double = 1.0

    var body: some View {
        ZStack {
            // Solid opaque background — this kills the double-signature bleed-through
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: Brand.Layout.spacingS) {
                Image(systemName: "signature")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(Brand.ember(for: scheme))
                    .symbolEffect(.drawOn.individually, options: .speed(1.5), isActive: drawOnActive)
                    .symbolEffect(.drawOff.individually, options: .speed(1.5), isActive: drawOffActive)

                Text("Signoff")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Brand.Ink.tertiary(for: scheme))
                    .opacity(0.7)
            }
            .opacity(splashOpacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zIndex(10)
        .onAppear { runSplashSequence() }
    }

    private func runSplashSequence() {
        guard !reduceMotion else {
            showSplash = false
            SignoffMenuContent.hasLoadedSplash = true
            return
        }

        // Phase 1: drawOn (already active via @State default = true)
        // Phase 2 — after drawOn completes (0.55s), hold (0.15s), then start drawOff
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55 + 0.15) {
            drawOnActive = false
            drawOffActive = true

            // Phase 4 — after drawOff (0.45s), fade out entire splash
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(.easeOut(duration: 0.2)) {
                    splashOpacity = 0.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showSplash = false
                    SignoffMenuContent.hasLoadedSplash = true
                }
            }
        }
    }
}

// MARK: - Bucket row (left column)

/// Bucket row for menu content — glassy hover fill, ember selection, shortcut badge.
@MainActor
private struct MenuBucketRow: View {
    let bucket: Bucket
    let isSelected: Bool
    let showShortcutHint: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var accent: Color { Brand.accent(for: bucket.id, scheme: scheme) }
    private var iconColor: Color { isSelected ? Brand.ember(for: scheme) : accent }
    private var nameFont: Font { Brand.Typography.callout.weight(.semibold) }
    private var primaryInk: Color { Brand.Ink.primary(for: scheme) }
    private var tertiaryInk: Color { Brand.Ink.tertiary(for: scheme) }
    private var emColor: Color { Brand.ember(for: scheme) }
    private var cardSurface: Color { Brand.Surface.card(for: scheme) }

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

    /// Inline keyboard shortcut hint — reflects the bound modifier (ctrlOpt by default).
    /// Honors the global "Show shortcut hints" setting so the column stays calm
    /// for users who've turned the hints off.
    private var shortcutText: String? {
        guard showShortcutHint else { return nil }
        let manager = ShortcutManager.shared
        let bindings = manager.decode(AppState.shared.settings.bucketShortcutsJSON)
        if let binding = bindings.first(where: { $0.bucketId == bucket.id }) {
            return manager.displayLabel(for: binding)
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
            HStack(spacing: Brand.Layout.spacingM) {
                bucketIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(bucket.name)
                        .font(nameFont)
                        .foregroundStyle(primaryInk)
                        .lineLimit(1)
                    Text(bucket.toneLabel)
                        .font(Brand.Typography.caption2)
                        .foregroundStyle(tertiaryInk.opacity(0.85))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

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
            .padding(.horizontal, Brand.Layout.spacingM)
            .padding(.vertical, Brand.Layout.spacingS)
            .background(
                RoundedRectangle(cornerRadius: Brand.Layout.radiusM, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Brand.Layout.radiusM, style: .continuous)
                    .stroke(isSelected ? emColor.opacity(0.35) : .clear,
                            lineWidth: Brand.Layout.hairline)
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

    private func shortcutHintForBucket(_ id: String) -> String {
        let manager = ShortcutManager.shared
        let bindings = manager.decode(AppState.shared.settings.bucketShortcutsJSON)
        if let binding = bindings.first(where: { $0.bucketId == id }) {
            return "Shortcut: \(manager.displayLabel(for: binding)) — Click to select, then Generate"
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

                Text("Pick a voice on the left, then Generate & Paste.")
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

// MARK: - Copy Toast

/// Delightful toast confirmation for copy/share actions
@MainActor
private struct CopyToastView: View {
    let message: String

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

/// Full-page signed-off history — accessible via the clock icon in the footer.
/// Same 580 pt ideal width as the main popover surface, with a back button to return.
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
                        ForEach(appState.recentGenerations, id: \.id) { gen in
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
            Text("Generated signoffs will appear here so you can reuse a good one.")
                .font(Brand.Typography.callout)
                .foregroundStyle(Brand.Ink.secondary(for: scheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Brand.Layout.spacingXL)
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
/// action bar (copy, thumbs, trash).
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
