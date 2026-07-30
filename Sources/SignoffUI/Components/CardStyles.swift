import SwiftUI
import SignoffCore

/// Reusable visual styles for surfaces layered on the popover base.
/// Flat elevated fills only — no drop shadows or materials inside NSPopover chrome.
public enum CardStyles {
    public struct StatusLineStyle: ViewModifier {
        public init() {}
        public func body(content: Content) -> some View {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
        }
    }
}

public extension View {
    func statusLine() -> some View { modifier(CardStyles.StatusLineStyle()) }
}

/// The signature preview card shown after a successful generation.
/// A drafted signoff on paper — monospace signature type, a small amber
/// underline finishing the phrase, and an honest provider badge.
public struct SignatureCardView: View {
    public let text: String
    public var providerKind: GenerationProviderKind?
    @Environment(\.colorScheme) private var scheme

    public init(text: String, providerKind: GenerationProviderKind? = nil) {
        self.text = text
        self.providerKind = providerKind
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.system(size: 15, weight: .regular, design: .monospaced))
                .kerning(0.5)
                .foregroundStyle(Brand.Semantic.textPrimary(for: scheme))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Amber underline — the signature flourish.
            LinearGradient(
                colors: [Brand.amber(for: scheme).opacity(0.85), Brand.amber(for: scheme).opacity(0)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 2)
            .clipShape(Capsule())

            if let providerKind {
                HStack(spacing: 5) {
                    Image(systemName: providerKind.badgeSystemImage)
                    Text(providerKind.badgeTitle)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(providerKind == .foundationModels
                                 ? Brand.amber(for: scheme)
                                 : Brand.Semantic.textSecondary(for: scheme))
                .accessibilityLabel("Provider: \(providerKind.badgeTitle)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Brand.Layout.cornerRadius, style: .continuous)
                .fill(Brand.Semantic.surfaceElevated(for: scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Brand.Layout.cornerRadius, style: .continuous)
                .stroke(Brand.Semantic.divider(for: scheme), lineWidth: Brand.Layout.hairline)
        )
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        if let providerKind {
            return "Generated signoff via \(providerKind.badgeTitle): \(text)"
        }
        return "Generated signoff: \(text)"
    }
}

/// Privacy badge — lock + "100% private", tinted by caller. Signals the
/// on-device promise at a glance without being loud.
public struct PrivacyBadge: View {
    @Environment(\.colorScheme) private var scheme
    public init() {}
    public var body: some View {
        Label("100% private", systemImage: "lock.fill")
            .font(.caption2.weight(.medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Brand.amber(for: scheme))
            .accessibilityLabel("100 percent private. All generation stays on your Mac.")
    }
}

/// Detailed VoiceProfile viewer for Settings → Privacy → "What I've Learned"
/// Shows the user's learned voice patterns with transparency and control.
public struct VoiceProfileDetailView: View {
    @Binding var display: VoiceProfileDisplay?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var showRawJSON = false

    public var body: some View {
        NavigationStack {
            Form {
                Section("Voice Profile Summary") {
                    if let display {
                        VStack(alignment: .leading, spacing: 12) {
                            // Formality bar
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Formality")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(display.formalityPercent)%")
                                        .font(.caption.monospacedDigit().weight(.medium))
                                }
                                ProgressView(value: Double(display.formalityPercent) / 100)
                                    .tint(Brand.amber(for: scheme))
                                Text(formalityLabel(display.formalityPercent))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Divider()

                            // Sentence length
                            HStack {
                                Text("Avg. sentence length")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.1f words", display.avgSentenceLength))
                                    .font(.callout.monospacedDigit().weight(.medium))
                            }

                            Divider()

                            // Punctuation style
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Punctuation style")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 12) {
                                    PunctuationStat(label: ".", value: display.punctuationStyle.periodPercent)
                                    PunctuationStat(label: "!", value: display.punctuationStyle.exclamationPercent)
                                    PunctuationStat(label: "?", value: display.punctuationStyle.questionPercent)
                                }
                            }

                            Divider()

                            // Emoji frequency
                            HStack {
                                Text("Emoji usage")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(display.emojiPercent)%")
                                    .font(.callout.monospacedDigit().weight(.medium))
                            }

                            Divider()

                            // Adopted closers
                            if !display.adoptedClosers.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Signoffs you use")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    FlowLayout(spacing: 6) {
                                        ForEach(display.adoptedClosers, id: \.self) { closer in
                                            Text(closer)
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(
                                                    Capsule()
                                                        .fill(Brand.amber(for: scheme).opacity(0.15))
                                                )
                                                .foregroundStyle(Brand.amber(for: scheme))
                                        }
                                    }
                                }
                            }

                            // Rejected closers
                            if !display.rejectedClosers.isEmpty {
                                Divider()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Signoffs you avoid (deleted/replaced)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    FlowLayout(spacing: 6) {
                                        ForEach(display.rejectedClosers, id: \.self) { closer in
                                            Text(closer)
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(
                                                    Capsule()
                                                        .fill(Color.red.opacity(0.15))
                                                )
                                                .foregroundStyle(.red)
                                        }
                                    }
                                }
                            }

                            Divider()

                            // Observation stats
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Quality observations")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Text("\(display.qualityObservations)")
                                        .font(.title3.monospacedDigit().weight(.semibold))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Noise observations")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Text("\(display.noiseObservations)")
                                        .font(.title3.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(.red)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Apps observed")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Text("\(display.observedApps.count)")
                                        .font(.title3.monospacedDigit().weight(.semibold))
                                }
                            }

                            Divider()

                            // Last updated
                            HStack {
                                Text("Last updated")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(display.lastUpdated, style: .relative)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                + Text(" ago")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }

                Section {
                    Button("View Raw Profile JSON") {
                        showRawJSON = true
                    }
                    .foregroundStyle(.blue)

                    Divider()

                    Button {
                        // Reset voice profile action
                        SilentLearningEngine.shared.reset()
                        display = VoiceProfile.shared.displaySummary
                    } label: {
                        Label("Reset My Voice", systemImage: "arrow.counterclockwise")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                } footer: {
                    Text("Resetting clears all learned patterns — formalities, rhythms, signoff preferences, and vocabulary. Signoff will start fresh next time you write.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("What I've Learned")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showRawJSON) {
                RawProfileJSONView(profile: VoiceProfile.shared)
            }
        }
    }

    private func formalityLabel(_ percent: Int) -> String {
        if percent >= 70 { return "Formal / Professional register" }
        if percent >= 40 { return "Balanced register" }
        return "Casual / Conversational register"
    }
}

private struct PunctuationStat: View {
    let label: String
    let value: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(Int(value))%")
                .font(.caption.monospacedDigit().weight(.medium))
        }
    }
}

/// Simple flow layout for wrapping chips
struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var row = 0
        var x: CGFloat = 0
        var maxWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for size in sizes {
            if x + size.width > (proposal.width ?? 400) && x > 0 {
                maxWidth = max(maxWidth, x)
                x = 0
                row += 1
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        maxWidth = max(maxWidth, x)
        return CGSize(width: maxWidth, height: CGFloat(row + 1) * rowHeight + CGFloat(max(0, row)) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Raw JSON viewer for the VoiceProfile
struct RawProfileJSONView: View {
    let profile: VoiceProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            ScrollView {
                if let data = try? JSONEncoder().encode(profile.displaySummary),
                   let json = try? JSONSerialization.jsonObject(with: data),
                   let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
                   let string = String(data: pretty, encoding: .utf8) {
                    Text(string)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                        .padding()
                } else {
                    Text("Unable to serialize profile")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .navigationTitle("Raw VoiceProfile JSON")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if let data = try? JSONEncoder().encode(profile.displaySummary),
                           let json = try? JSONSerialization.jsonObject(with: data),
                           let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
                           let string = String(data: pretty, encoding: .utf8) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(string, forType: .string)
                        }
                    } label: {
                        Label("Copy JSON", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

/// Compact VoiceProfile summary for Settings → Privacy → "What I've Learned"
public struct VoiceProfileSummaryView: View {
    let display: VoiceProfileDisplay
    @Environment(\.colorScheme) private var scheme

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Formality bar
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Formality")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    ProgressView(value: Double(display.formalityPercent) / 100)
                        .tint(Brand.amber(for: scheme))
                    Text("\(display.formalityPercent)%")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .frame(width: 40, alignment: .trailing)
                    Text(formalityLabel(display.formalityPercent))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Divider().padding(.vertical, 4)

            // Stats grid
            HStack(spacing: 16) {
                StatChip(label: "Avg. sentence", value: String(format: "%.1f", display.avgSentenceLength), unit: "words")
                StatChip(label: "Emoji", value: "\(display.emojiPercent)%")
                StatChip(label: "Quality obs.", value: "\(display.qualityObservations)")
                StatChip(label: "Noise obs.", value: "\(display.noiseObservations)", valueColor: .red)
            }

            Divider().padding(.vertical, 4)

            // Punctuation style
            HStack(spacing: 12) {
                Text("Punctuation")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
                HStack(spacing: 8) {
                    Text(". \(Int(display.punctuationStyle.periodPercent))%")
                    Text("! \(Int(display.punctuationStyle.exclamationPercent))%")
                    Text("? \(Int(display.punctuationStyle.questionPercent))%")
                }
                .font(.caption.monospacedDigit().weight(.medium))
                Spacer()
            }

            // Adopted closers
            if !display.adoptedClosers.isEmpty {
                Divider().padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Signoffs you use")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 4) {
                        ForEach(display.adoptedClosers.suffix(5), id: \.self) { closer in
                            Text(closer)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Brand.amber(for: scheme).opacity(0.15))
                                )
                                .foregroundStyle(Brand.amber(for: scheme))
                        }
                    }
                }
            }

            // Rejected closers
            if !display.rejectedClosers.isEmpty {
                Divider().padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Signoffs you avoid")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 4) {
                        ForEach(display.rejectedClosers.suffix(3), id: \.self) { closer in
                            Text(closer)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.red.opacity(0.15))
                                )
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formalityLabel(_ percent: Int) -> String {
        if percent >= 70 { return "Formal / Professional" }
        if percent >= 40 { return "Balanced" }
        return "Casual / Conversational"
    }
}

private struct StatChip: View {
    let label: String
    let value: String
    var unit: String = ""
    var valueColor: Color = .primary
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            HStack(spacing: 2) {
                Text(value)
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(valueColor)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.04))
        )
    }
}
