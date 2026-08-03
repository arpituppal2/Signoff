import SwiftUI
import SignoffCore
import AppKit
import os.log

/// Menu content for MenuBarExtra — the primary, always-available surface.
///
/// Layout philosophy: a calm, single-column surface that reads like a native
/// macOS utility. Top = Voice picker (compact segmented control), Middle =
/// Result area (the generated signoff), Bottom = Primary action + minimal footer.
///
/// Hierarchy: "Generate & Paste" is the single primary action. Voice selection
/// is compact. Footer has icon-only utility buttons with native tooltips.
/// No decorative borders, no giant empty panels, no text labels in chrome.
@MainActor
public struct SignoffMenuContent: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow

    // Toast state for copy confirmation
    @State private var showCopyToast = false
    @State private var toastMessage = ""

    // Splash animation state — the overlay owns its own timeline; the parent
    // only flips this flag to present/dismiss it.
    @State private var showSplash = false

    /// Tracks whether the first-open animation has completed for this session
    @State private var hasCompletedFirstAnimation = false

    // Voice hover state
    @State private var hoveredVoiceId: String?

    // In-popover navigation: the popover can show the main generate surface
    // OR the history list in place (footer clock button → .history). Back
    // chevron in the history header returns to .main. Kept as a single @State
    // enum so a route flip is one render (no render-loop risk — no @Published
    // round-trips).
    @State private var route: PopoverRoute = .main

    // User undergoing generation?
    private var isGenerating: Bool { appState.isGenerating }

    public init() {}

    public var body: some View {
        ZStack {
            contentForRoute
                .padding(.horizontal, Brand.Layout.spacingM)  // 16pt
                .padding(.vertical, Brand.Layout.spacingM)    // 16pt
                .frame(width: 340, alignment: .leading)

            // Copy confirmation toast overlay
            if showCopyToast {
                CopyToastView(message: toastMessage)
                    .transition(
                        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))
                    )
                    .zIndex(1)
            }

            // First-open splash overlay
            if showSplash {
                SplashOverlay(reduceMotion: reduceMotion, onComplete: {
                    withAnimation(.easeOut(duration: 0.15)) {
                        showSplash = false
                    }
                })
                .zIndex(10)
            }
        }
        .animation(Brand.Motion.safe(.spring(response: 0.35, dampingFraction: 0.8), reduceMotion: reduceMotion), value: showCopyToast)
        .background(popoverBackground)
        .task(id: "initialization") {
            // Runs once when the menu content first appears
            await initializeIfNeeded()
        }
        .onChange(of: appState.showOnboarding) { _, shouldShow in
            if shouldShow { openWindow(id: "signoff.onboarding") }
        }
        .onReceive(NotificationCenter.default.publisher(for: .signoffOnboardingRequested)) { _ in
            if appState.showOnboarding { openWindow(id: "signoff.onboarding") }
        }
    }

    // MARK: - Background

    private var popoverBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).opacity(0.35)
            if route == .main, let bucket = appState.selectedBucket {
                Brand.accent(for: bucket.id, scheme: scheme).opacity(0.05)
            }
        }
        .background(.regularMaterial)
    }

    /// Routes the popover between the main generate surface and the in-popover
    /// history list. The history route reuses `HistoryListContent` (the same
    /// rows/window/Settings-tab component), sized to the 340pt popover with a
    /// back chevron that flips back to `.main`. `onGenerate` drives the
    /// empty-state button straight into the main generate flow.
    @ViewBuilder
    private var contentForRoute: some View {
        switch route {
        case .main:
            mainContent
                .transition(routeTransition)
        case .history:
            HistoryListContent(
                onBack: {
                    withAnimation(Brand.Motion.safe(.easeInOut(duration: 0.2), reduceMotion: reduceMotion)) {
                        route = .main
                    }
                },
                onGenerate: {
                    withAnimation(Brand.Motion.safe(.easeInOut(duration: 0.2), reduceMotion: reduceMotion)) {
                        route = .main
                    }
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    Task { await appState.generateNow(shouldAutoPaste: true) }
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(routeTransition)
        }
    }

    private var routeTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing))
    }

    // MARK: - Main Content (Single Column)

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: Brand.Layout.spacingM) {
            // 1. Voice Picker — compact segmented row
            voicePickerSection

            // 2. Result Area — the focal point
            resultSection

            // 3. Primary Action
            primaryActionButton

            // 4. Minimal Footer — icon-only utility buttons
            footer
        }
    }

    // MARK: - Voice Picker (Compact Segmented Control)

    private var voicePickerSection: some View {
        VStack(spacing: Brand.Layout.spacingXS) {
            HStack(spacing: Brand.Layout.spacingXS) {
                ForEach(appState.buckets, id: \.id) { bucket in
                    voiceSegment(for: bucket)
                }
            }
            // Center the bucket group as a whole in the 340pt popover.
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// Extracted so the surrounding `ForEach`/`HStack` expression stays small
    /// enough for the type-checker (an inline `VoiceSegmentButton(...)` with
    /// two trailing closures + comparison subexpressions was timing it out).
    @ViewBuilder
    private func voiceSegment(for bucket: Bucket) -> some View {
        VoiceSegmentButton(
            bucket: bucket,
            isSelected: appState.selectedBucketId == bucket.id,
            isHovered: hoveredVoiceId == bucket.id,
            action: { appState.selectedBucketId = bucket.id },
            onHover: { hovering in
                hoveredVoiceId = hovering ? bucket.id : nil
            }
        )
    }

    // MARK: - Result Area

    @ViewBuilder
    private var resultSection: some View {
        if let storeFailure = failureFromStoreRecovery(appState.storeRecovery) {
            ErrorFixCard(
                failure: storeFailure,
                onAction: handleFixAction,
                onDismiss: { appState.storeRecovery = nil }
            )
        } else if let txt = appState.generatedText, !isGenerating {
            SignatureCardView(text: txt)
            .transition(
                reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top))
            )
        } else if isGenerating {
            GeneratingView()
                .frame(minHeight: 60)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel("Generating signoff")
        } else if shouldShowFMAvailabilityCard {
            ErrorFixCard(
                failure: .fmUnavailable,
                onAction: handleFixAction,
                onDismiss: { }
            )
        } else {
            // Empty state — minimal, no "No signoff yet" text
            EmptyResultView(selectedBucket: appState.selectedBucket)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var shouldShowFMAvailabilityCard: Bool {
        let fmAvailability = FoundationModelsAvailability.shared
        switch fmAvailability.status {
        case .appleIntelligenceNotEnabled, .modelNotReady: return true
        default: return false
        }
    }

    // MARK: - Primary Action

    private var primaryActionButton: some View {
        Button {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            Task { await appState.generateNow(shouldAutoPaste: true) }
        } label: {
            HStack(spacing: Brand.Layout.spacingS) {
                Image(systemName: isGenerating ? "signature" : "arrow.right.to.line")
                    .font(.system(size: 13, weight: isGenerating ? .medium : .semibold))
                    .foregroundStyle(isGenerating ? Brand.ember(for: scheme) : .primary)
                    .symbolEffect(.pulse, options: .repeating, isActive: isGenerating && !reduceMotion)
                Text("Generate & Paste")
                    .font(Brand.Typography.callout.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Brand.Layout.spacingS)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Brand.ember(for: scheme))
        .disabled(isGenerating || appState.selectedBucket == nil)
        .accessibilityHint("Generate a signoff and paste it at your cursor.")
        .sensoryFeedback(.impact, trigger: appState.generatedText)
    }

    // MARK: - Footer (Icon-only utility buttons)

    private var footer: some View {
        HStack(spacing: Brand.Layout.spacingS) {
            Spacer(minLength: 0)

            // Icon-only utility buttons (trailing)
            UtilityIconButton(
                symbol: "clock.arrow.circlepath",
                label: "History",
                help: "History (in menu bar)",
                action: openHistoryInPopover
            )
            UtilityIconButton(
                symbol: "gearshape",
                label: "Settings",
                help: "Settings",
                action: openSettings
            )
            UtilityIconButton(
                symbol: "power",
                label: "Quit",
                help: "Quit Signoff",
                role: .destructive,
                action: { NSApp.terminate(nil) }
            )
        }
    }

    /// One-shot: open the hidden Settings-context window so its
    /// `@Environment(\.openSettings)` + `.onReceive` stay live for the app
    /// lifetime. Without this, `SettingsContextView` never instantiates and
    /// every `.openSettingsShortcutTriggered` post (popover buttons, ⌘,) falls
    /// into the void. Opened once at first Settings need; parked offscreen by
    /// its own `.onAppear`.
    private static var didOpenSettingsContext = false

    private func ensureSettingsContextWindow() {
        guard !Self.didOpenSettingsContext else { return }
        Self.didOpenSettingsContext = true
        openWindow(id: "signoff.settings-context")
    }

    private func openSettings() {
        // Make the context window live first (subscribes the .onReceive),
        // then activate (we run under .accessory — without this the Settings
        // window opens behind everything and never becomes key), then post.
        ensureSettingsContextWindow()
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .openSettingsShortcutTriggered, object: nil)
    }

    private func openHistoryInPopover() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        withAnimation(Brand.Motion.safe(.easeInOut(duration: 0.2), reduceMotion: reduceMotion)) {
            route = .history
        }
    }

    private enum PopoverRoute {
        case main
        case history
    }

    // MARK: - Initialization

    private func initializeIfNeeded() async {
        FoundationModelsAvailability.shared.refresh()
        appState.hasOpenedMenuBar = true
        NotificationCenter.default.post(name: .signoffMenuBarAppUsed, object: nil)

        // Trigger first-open animation if not yet completed
        if !hasCompletedFirstAnimation {
            hasCompletedFirstAnimation = true
            showSplash = true
        }
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

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        showToast("Copied")
    }

    private func showToast(_ message: String) {
        toastMessage = message
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
}

// MARK: - Voice Segment Button (Compact)

@MainActor
private struct VoiceSegmentButton: View {
    let bucket: Bucket
    let isSelected: Bool
    let isHovered: Bool
    let action: () -> Void
    let onHover: (Bool) -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color { Brand.accent(for: bucket.id, scheme: scheme) }
    private var iconColor: Color { isSelected ? Brand.ember(for: scheme) : accent }

    var body: some View {
        Button(action: {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            withAnimation(Brand.Motion.safe(.spring(response: 0.28, dampingFraction: 0.75), reduceMotion: reduceMotion)) {
                action()
            }
        }) {
            VStack(spacing: 2) {
                Image(systemName: bucket.iconSymbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(iconColor)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 22, height: 22)
                    .symbolEffect(.bounce, value: isSelected)

                Text(bucket.name)
                    .font(Brand.Typography.caption2.weight(.medium))
                    .foregroundStyle(isSelected ? Brand.Ink.primary(for: scheme) : Brand.Ink.secondary(for: scheme))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Brand.Layout.radiusS, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Brand.Layout.radiusS, style: .continuous)
                    .stroke(
                        isSelected ? Brand.ember(for: scheme).opacity(0.5)
                            : (isHovered ? accent.opacity(0.25) : Brand.Surface.divider(for: scheme)),
                        lineWidth: isSelected ? Brand.Layout.borderWeight : Brand.Layout.hairline
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { onHover($0) }
        .help("Select \(bucket.name) voice")
        .accessibilityLabel("\(bucket.name) voice")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Select this voice style")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var backgroundFill: Color {
        if isSelected {
            return Brand.Surface.card(for: scheme).opacity(0.85)
        }
        if isHovered {
            return Brand.Surface.card(for: scheme).opacity(0.4)
        }
        return .clear
    }
}

// MARK: - Utility Icon Button (Icon-only with tooltip + accessibility)

@MainActor
private struct UtilityIconButton: View {
    let symbol: String
    let label: String
    let help: String
    var role: ButtonRole? = nil
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(buttonForeground)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.clear)
        )
        .help(help)
        .accessibilityLabel(label)
        .accessibilityHint("Activate to \(help.lowercased())")
    }

    private var buttonForeground: Color {
        if role == .destructive {
            return Color.red.opacity(0.85)
        }
        return Brand.Ink.secondary(for: scheme)
    }
}

// MARK: - Generating View

@MainActor
private struct GeneratingView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Brand.Layout.spacingS) {
            // The signature glyph WRITES ON while we generate — the pen strokes
            // the signature, over and over, until the signoff lands. The
            // drawOn/drawOff cycle (`.repeating`) is the generation affordance
            // here, not the previous `pulse` (a generic "busy" indicator with
            // no sign-off metaphor). Matches the menu-bar label's drawOn while
            // generating, so the popover and the menu bar tell one story.
            // Reduce Motion users get a static glyph — no animated stroke.
            Image(systemName: "signature")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Brand.ember(for: scheme))
                .symbolEffect(
                    .drawOn.individually,
                    options: .repeating,
                    isActive: !reduceMotion
                )

            Text("Generating…")
                .font(Brand.Typography.callout)
                .foregroundStyle(Brand.Ink.secondary(for: scheme))
        }
        .padding(.vertical, Brand.Layout.spacingM)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Empty Result View (Minimal)

@MainActor
private struct EmptyResultView: View {
    let selectedBucket: Bucket?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: Brand.Layout.spacingS) {
            // Subtle bucket indicator
            if let bucket = selectedBucket {
                Image(systemName: bucket.iconSymbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Brand.accent(for: bucket.id, scheme: scheme).opacity(0.5))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Brand.accent(for: bucket.id, scheme: scheme).opacity(0.08))
                    )
            } else {
                Image(systemName: "signature")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Brand.Ink.tertiary(for: scheme).opacity(0.5))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Brand.Surface.divider(for: scheme).opacity(0.3))
                    )
            }
        }
        .padding(.vertical, Brand.Layout.spacingL)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Copy Toast

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
                    .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
            )
            .padding(.bottom, 80) // Above menu bar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - First-Open Splash Animation

/// Runs the drawOn → drawOff → fade sequence exactly once. The overlay owns
/// its own timeline, driven from `onAppear` as a single linear async chain —
/// no `.onChange(of:)` dependency on an initial binding value (which SwiftUI
/// does not fire for the initial value, and a previous revision relied on that
/// and left the splash stuck on the signature forever).
private struct SplashOverlay: View {
    @Environment(\.colorScheme) private var scheme

    let reduceMotion: Bool
    let onComplete: () -> Void

    // Animation triggers — flipped along the timeline. isActive toggles drive
    // the symbol effects; keep them stable SwiftUI values (not recreated).
    @State private var drawOnTrigger = false
    @State private var drawOffTrigger = false
    @State private var overlayOpacity: Double = 1.0
    @State private var completed = false

    var body: some View {
        ZStack {
            // Solid opaque background — prevents any content bleed-through
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            // The signature symbol — animates through drawOn → drawOff → fade
            Image(systemName: "signature")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(Brand.ember(for: scheme))
                .symbolEffect(.drawOn.individually, options: .speed(1.5), isActive: drawOnTrigger)
                .symbolEffect(.drawOff.individually, options: .speed(1.5), isActive: drawOffTrigger)
                .opacity(overlayOpacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "splash") {
            await runTimeline()
        }
    }

    /// Drives the full sequence once. Task is tied to the overlay's lifetime —
    /// if the overlay is torn down early (e.g. popover dismissed), the Task is
    /// cancelled and the sleeps bail out; no orphaned state mutations.
    /// Includes a 3-second hard timeout as a fallback to ensure the splash never
    /// blocks UI if animations stall.
    @MainActor
    private func runTimeline() async {
        guard !completed else { return }

        // Reduce Motion: skip the ceremony, just dismiss.
        guard !reduceMotion else {
            completed = true
            onComplete()
            return
        }

        completed = true

        // Run the timeline with a hard 3-second timeout using a simple approach
        // Create a timeout check task
        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            // If we reach here, the timeline didn't complete in time
            if !Task.isCancelled && !completed {
                withAnimation(.easeOut(duration: 0.15)) {
                    overlayOpacity = 0.0
                }
                onComplete()
            }
        }

        // Run the animation sequence
        do {
            // Let layout settle for one frame so the symbol is onscreen before the
            // effect starts (drawOn on a not-yet-rendered symbol can no-op).
            try await Task.sleep(for: .milliseconds(40))

            // drawOn — the signature is drawn in (pen stroke). ~0.55s at speed 1.5.
            drawOnTrigger = true
            try await Task.sleep(for: .milliseconds(650))

            // drawOff — the signature is retracted. ~0.45s at speed 1.5.
            drawOffTrigger = true
            try await Task.sleep(for: .milliseconds(500))

            // Fade the whole overlay out, then hand control back to the parent.
            withAnimation(.easeOut(duration: 0.18)) {
                overlayOpacity = 0.0
            }
            try await Task.sleep(for: .milliseconds(180))

            onComplete()
        } catch {
            // Task cancelled (overlay dismissed) — cancel timeout and call onComplete
            timeoutTask.cancel()
            onComplete()
        }

        // Cancel the timeout task since we completed normally
        timeoutTask.cancel()
    }
}