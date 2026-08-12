import SwiftUI
import SignoffCore

/// Surface-agnostic history list — the shared rendering used by three hosts:
/// the standalone History window, the in-popover history view, and the
/// Settings → History tab.
///
/// Owns: the history rows (with thumbs feedback + delete), the empty state,
/// and the delete-confirm alert. Hosts supply chrome by passing closures:
/// `onBack` shows a "Back" chevron (popover); omit it for window/Settings.
/// `onGenerate` wires the empty-state's "Generate Signoff" button.
@MainActor
public struct HistoryListContent: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var scheme

    /// Chevron-back action. When nil, no back button is shown (window, Settings).
    var onBack: (() -> Void)?

    /// Empty-state generate action. When nil, the empty state shows no button.
    var onGenerate: (() -> Void)?

    /// Top-right header action that opens the detailed History view in
    /// Settings — the command-icon button opposite the back chevron at
    /// top-left. When nil, the button is hidden. Pass nil from the
    /// Settings → History tab itself (the button would be redundant
    /// "open what's already open") and from any host that shouldn't surface it.
    var onOpenSettingsHistory: (() -> Void)?

    @State private var showDeleteConfirm = false
    @State private var generationToDelete: SignoffGeneration?

    public init(onBack: (() -> Void)? = nil,
                onGenerate: (() -> Void)? = nil,
                onOpenSettingsHistory: (() -> Void)? = nil) {
        self.onBack = onBack
        self.onGenerate = onGenerate
        self.onOpenSettingsHistory = onOpenSettingsHistory
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Brand.Layout.spacingM) {
            header

            if appState.recentGenerations.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Brand.Layout.spacingXS) {
                        ForEach(appState.recentGenerations) { generation in
                            HistoryRowView(
                                generation: generation,
                                onDelete: { gen in
                                    generationToDelete = gen
                                    showDeleteConfirm = true
                                }
                            )
                        }
                    }
                    .padding(.horizontal, Brand.Layout.spacingM)
                    .padding(.bottom, Brand.Layout.spacingL)
                }
            }
        }
        .alert("Delete History", isPresented: $showDeleteConfirm) {
            if let generation = generationToDelete {
                Button("Delete", role: .destructive) {
                    appState.deleteGeneration(generation)
                }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("Clear All", role: .destructive) {
                    appState.clearHistory()
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            if let generation = generationToDelete {
                Text("Delete \"\(generation.text.prefix(50))…\" from history?")
            } else {
                Text("This will permanently remove all history entries. Favorites are kept. This cannot be undone.")
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: Brand.Layout.spacingS) {
            if let onBack {
                Button {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    onBack()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Back")
                            .font(Brand.Typography.callout.weight(.medium))
                    }
                    .foregroundStyle(Brand.Ink.secondary(for: scheme))
                }
                .buttonStyle(.plain)
                .help(onBackLabel)
            }

            Spacer()

            Text("History")
                .font(Brand.Typography.headline.weight(.semibold))
                .foregroundStyle(Brand.Ink.primary(for: scheme))

            Spacer()

            // Trailing cluster: "Clear All" (when history non-empty) sits next
            // to the command-icon button that opens the detailed History view in
            // Settings — opposite the back button at top-left. The command
            // button is wired only by hosts where it's meaningful (popover,
            // standalone window); the Settings → History tab passes nil so it
            // doesn't render a redundant "open what's already open" button.
            HStack(spacing: Brand.Layout.spacingS) {
                if !appState.recentGenerations.isEmpty {
                    Button {
                        generationToDelete = nil // nil = clear all
                        showDeleteConfirm = true
                    } label: {
                        Text("Clear All")
                            .font(Brand.Typography.caption1.weight(.medium))
                            .foregroundStyle(Color.red.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help("Clear entire history")
                }

                if let onOpenSettingsHistory {
                    Button {
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                        onOpenSettingsHistory()
                    } label: {
                        Image(systemName: "command")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(Brand.Ink.secondary(for: scheme))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open detailed History in Settings")
                    .accessibilityLabel("Open detailed History in Settings")
                    .accessibilityHint("Opens the Settings window at the History tab")
                }
            }
        }
        .padding(.horizontal, Brand.Layout.spacingM)
    }

    private var onBackLabel: String {
        // Popover returns to the menu; window dismisses to the menu bar.
        onBack != nil ? "Return to menu bar" : ""
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: Brand.Layout.spacingM) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Brand.Ink.tertiary(for: scheme))
                .frame(width: 64, height: 64)
                .background(
                    Circle()
                        .fill(Brand.Surface.divider(for: scheme).opacity(0.3))
                )

            VStack(spacing: Brand.Layout.spacingXS) {
                Text("No History Yet")
                    .font(Brand.Typography.headline.weight(.semibold))
                    .foregroundStyle(Brand.Ink.primary(for: scheme))

                Text("Generate your first signoff to see it here.")
                    .font(Brand.Typography.callout)
                    .foregroundStyle(Brand.Ink.secondary(for: scheme))
                    .multilineTextAlignment(.center)
            }

            if let onGenerate {
                Button {
                    onGenerate()
                } label: {
                    Text("Generate Signoff")
                        .font(Brand.Typography.callout.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Brand.ember(for: scheme))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Brand.Layout.spacingL)
    }
}

/// Standalone History window host. Thin wrapper around `HistoryListContent`;
/// kept as its own scene (Window id "signoff.history") so it remains available
/// as a larger surface if ever opened directly (reopen / future affordances).
@MainActor
public struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        HistoryListContent(
            onBack: { dismiss() },
            onGenerate: { Task { await appState.generateNow() } },
            onOpenSettingsHistory: {
                // The Settings-context window is alive from launch
                // (MenuBarLabelView opens it once), so posting the routed
                // notification brings up Settings at the History tab — then
                // dismiss this standalone window.
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .openSettingsShortcutTriggered, object: SettingsPane.history)
                dismiss()
            }
        )
        .frame(width: 420, height: 560)
        .background(.regularMaterial)
    }
}

/// Individual history row with bucket badge, timestamp, thumbs feedback, and delete action.
///
/// The thumbs are NOT a placebo: `applyFeedback(_:liked:)` persists
/// `isFavorite`, and favorites count double in `AppState.preferredRegister`
/// — so thumbing up a signoff biases future generations toward its register.
/// Thumbs-down clears the favorite (un-weights it).
@MainActor
private struct HistoryRowView: View {
    let generation: SignoffGeneration
    let onDelete: (SignoffGeneration) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var scheme

    private var bucketForGeneration: Bucket? {
        return appState.buckets.first { $0.id == generation.bucketId }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Brand.Layout.spacingS) {
            // Bucket indicator
            if let bucket = bucketForGeneration {
                Image(systemName: bucket.iconSymbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Brand.accent(for: bucket.id, scheme: scheme))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Brand.accent(for: bucket.id, scheme: scheme).opacity(0.1))
                    )
            } else {
                Image(systemName: "signature")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Brand.Ink.tertiary(for: scheme))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Brand.Surface.divider(for: scheme).opacity(0.3))
                    )
            }

            // Text + metadata. `maxWidth: .infinity` lets this stack claim the
            // full row width so the signoff wraps wide and the trash sits at the
            // true trailing edge. The prior `Spacer(minLength: 0)` plus an
            // invisible `.opacity(0)` delete button collapsed rows to ~60%:
            // the flexible Spacer stole the trailing width and SwiftUI proposed
            // only the Text's narrow intrinsic width to this stack, so the
            // signoff wrapped early and the row read as bunched-left. No Spacer
            // and no invisible duplicate now — the trash is a real, always-
            // present trailing sibling.
            VStack(alignment: .leading, spacing: 2) {
                Text(generation.text)
                    .font(Brand.Typography.body)
                    .foregroundStyle(Brand.Ink.primary(for: scheme))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                feedbackRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Delete — a real trailing sibling. Subtly always-visible at 30%
            // so it's discoverable without dominating the row (the prior
            // `.onHover` was a no-op and the overlay was a cheat for the same
            // effect, which the simpler layout no longer needs).
            Button {
                onDelete(generation)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete from history")
            .opacity(0.3)
        }
        .padding(.horizontal, Brand.Layout.spacingS)
        .padding(.vertical, Brand.Layout.spacingXS)
        .background(
            RoundedRectangle(cornerRadius: Brand.Layout.radiusS, style: .continuous)
                .fill(Color.clear)
        )
        .animation(.easeInOut(duration: 0.15), value: false)
    }

    /// Metadata + thumbs feedback row. The timestamp and "On-device" provider
    /// badge were removed: the app runs 100% locally (the badge stated the
    /// obvious) and a relative timestamp is noise on a generation list. The
    /// color-coded bucket name stays — it gives voice context that the leading
    /// glyph alone can't — and the thumbs stay, since they persist favorite
    /// status which weights the predictive-register picker
    /// (AppState.preferredRegister).
    @ViewBuilder
    private var feedbackRow: some View {
        HStack(spacing: Brand.Layout.spacingXS) {
            if let bucket = bucketForGeneration {
                Text(bucket.name)
                    .font(Brand.Typography.caption2.weight(.medium))
                    .foregroundStyle(Brand.accent(for: bucket.id, scheme: scheme))
            }

            thumbsButton(liked: true, filled: generation.isFavorite)
            thumbsButton(liked: false, filled: false)
        }
    }

    @ViewBuilder
    private func thumbsButton(liked: Bool, filled: Bool) -> some View {
        Button {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            appState.applyFeedback(generation, liked: liked)
        } label: {
            Image(systemName: liked
                  ? (filled ? "hand.thumbsup.fill" : "hand.thumbsup")
                  : "hand.thumbsdown")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(thumbsColor(liked: liked, filled: filled))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(liked ? "Good one — keep more like this" : "Not this style")
    }

    private func thumbsColor(liked: Bool, filled: Bool) -> Color {
        if liked && filled {
            return Brand.ember(for: scheme)
        }
        return Brand.Ink.tertiary(for: scheme)
    }
}
