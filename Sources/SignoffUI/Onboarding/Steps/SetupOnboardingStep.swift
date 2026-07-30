import SwiftUI
import Combine
import SignoffCore

// MARK: - Multi-Step Onboarding with Brand Moments

/// 5-step first-launch onboarding per brand spec (Section 6.4):
/// 1. Welcome — animated signature writing itself + neural engine pitch
/// 2. Profile — name + self-description + live voice preview (FMF vs generic)
/// 3. Accessibility — demo: generate → paste in fake text field
/// 4. Input Monitoring — shortcut diagram with amber highlights
/// 5. Bucket Tour — horizontal scroll with live FMF generation per bucket
struct SetupOnboardingStep: View {
    @StateObject private var appState = AppState.shared
    @Environment(\.colorScheme) private var scheme

    // Permissions state
    @State private var accessibilityGranted: Bool = AXIsProcessTrusted()
    @State private var inputMonitoringGranted: Bool = InputMonitoringAccess.isGranted()
    @State private var pollTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    // Profile state
    @State private var name: String = ""
    @State private var selfDescription: String = ""

    // Step management - 5 steps per brand spec
    @State private var currentStep: OnboardingStep = .welcome
    @State private var showStepTransition = false

    // Live generation for bucket tour
    @State private var bucketPreviewSignoffs: [String: String] = [:]
    @State private var isGeneratingBucketPreview: [String: Bool] = [:]
    @State private var bucketPreviewError: [String: String] = [:]

    // Live voice preview generation (step 2)
    @State private var voicePreviewSignoff: String = ""
    @State private var isGeneratingVoicePreview = false

    // Accessibility demo generation (step 3)
    @State private var demoSignoff: String = ""
    @State private var isDemoGenerating = false
    @State private var showDemoPaste = false

    private var shortcuts: [(key: String, label: String)] = [
        ("⌃⌘1", "Generate a signoff"),
        ("⌃⌘2–6", "Swap the tone / bucket"),
        ("⇧⌘C", "Copy your last signoff"),
        ("⌘,", "Open Settings"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            StepIndicatorView(currentStep: currentStep)

            // Step content with transition
            ZStack {
                Group {
                    switch currentStep {
                    case .welcome:
                        WelcomeStepView(onContinue: { advanceStep() })
                    case .profile:
                        ProfileStepView(
                            name: $name,
                            selfDescription: $selfDescription,
                            voicePreviewSignoff: $voicePreviewSignoff,
                            isGeneratingVoicePreview: $isGeneratingVoicePreview,
                            onGenerateVoicePreview: generateVoicePreview,
                            onContinue: { advanceStep() }
                        )
                    case .accessibility:
                        AccessibilityDemoStepView(
                            demoSignoff: $demoSignoff,
                            isGenerating: $isDemoGenerating,
                            showDemoPaste: $showDemoPaste,
                            onGenerateDemo: generateAccessibilityDemo,
                            onContinue: { advanceStep() }
                        )
                    case .inputMonitoring:
                        InputMonitoringStepView(
                            inputMonitoringGranted: $inputMonitoringGranted,
                            onGrantAction: grantInputMonitoring,
                            onContinue: { advanceStep() }
                        )
                    case .bucketTour:
                        BucketTourStepView(
                            bucketPreviewSignoffs: $bucketPreviewSignoffs,
                            isGeneratingBucketPreview: $isGeneratingBucketPreview,
                            bucketPreviewError: $bucketPreviewError,
                            onContinue: { advanceStep() },
                            onBack: { backStep() },
                            onRegenerate: regenerateBucketPreview
                        )
                    }
                }
                .opacity(showStepTransition ? 1 : 0)
                .offset(y: showStepTransition ? 0 : 10)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentStep)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showStepTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Footer with navigation
            OnboardingFooter(
                currentStep: currentStep,
                onBack: backStep,
                onContinue: advanceStep,
                onSkip: { currentStep = .allCases.last!; advanceStep() }
            )
        }
        .frame(width: 560, height: 540)
        .background(Brand.Semantic.surfaceBase(for: scheme))
        .onAppear {
            refreshPermissions()
            showStepTransition = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
        .onReceive(pollTimer) { _ in refreshPermissions() }
    }

    private func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = InputMonitoringAccess.isGranted()
        appState.paste.refreshPermissionState()
    }

    private func grantAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt": NSNumber(value: true)] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        accessibilityGranted = AXIsProcessTrusted()
        if !accessibilityGranted {
            AccessibilityAccess.openSystemSettings()
        } else {
            Task { @MainActor in
                await AppState.shared.startLearningEngineIfNeeded()
            }
        }
    }

    private func grantInputMonitoring() {
        _ = InputMonitoringAccess.request()
        inputMonitoringGranted = InputMonitoringAccess.isGranted()
        if !inputMonitoringGranted {
            InputMonitoringAccess.openSystemSettings()
        }
    }

    private func advanceStep() {
        let nextIndex = currentStep.index + 1
        if let next = OnboardingStep.allCases.first(where: { $0.index == nextIndex }) {
            showStepTransition = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                currentStep = next
                showStepTransition = true
                // Start generation when entering specific steps
                if next == .bucketTour {
                    Task { await generateBucketPreviews() }
                }
            }
        } else {
            finishOnboarding()
        }
    }

    private func backStep() {
        guard currentStep.index > 0 else { return }
        showStepTransition = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let prev = OnboardingStep.allCases.first(where: { $0.index == currentStep.index - 1 }) {
                currentStep = prev
                showStepTransition = true
            }
        }
    }

    private func finishOnboarding() {
        commitProfile()
        AppState.shared.markOnboardingCompleted()
    }

    private func commitProfile() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedDesc = selfDescription.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty || !trimmedDesc.isEmpty else { return }
        let updated = UserProfile(
            name: trimmedName.isEmpty ? " " : trimmedName,
            title: appState.profile.title,
            company: appState.profile.company,
            email: appState.profile.email,
            phone: appState.profile.phone,
            website: appState.profile.website,
            linkedin: appState.profile.linkedin,
            selfDescription: trimmedDesc,
            emojiEnabled: appState.profile.emojiEnabled
        )
        appState.profile = updated
        try? appState.persistence.saveProfile(updated)
    }

    @MainActor
    private func generateVoicePreview() async {
        isGeneratingVoicePreview = true
        defer { isGeneratingVoicePreview = false }

        // Use FMF for a "fast" bucket to show the contrast
        let outcome = await GenerationService.shared.generate(
            bucketId: BucketID.standard.rawValue,
            profile: appState.profile,
            recentTexts: [],
            unhingedLevel: .regular,
            toneValue: 0.5,
            postfixMode: .nothing,
            customInstructions: "",
            phraseList: nil,
            ageGroup: appState.settings.generationAgeGroup
        )

        if case .success(let o) = outcome {
            voicePreviewSignoff = o.text.replacingOccurrences(of: "\n\n---\nPowered by Signoff", with: "")
        }
    }

    @MainActor
    private func generateAccessibilityDemo() async {
        isDemoGenerating = true
        defer { isDemoGenerating = false }

        // Generate a realistic demo signoff
        let outcome = await GenerationService.shared.generate(
            bucketId: BucketID.standard.rawValue,
            profile: appState.profile,
            recentTexts: [],
            unhingedLevel: .regular,
            toneValue: 0.5,
            postfixMode: .nothing,
            customInstructions: "",
            phraseList: nil,
            ageGroup: appState.settings.generationAgeGroup
        )

        if case .success(let o) = outcome {
            demoSignoff = o.text
            // Show the paste animation after a brief delay
            try? await Task.sleep(nanoseconds: 500_000_000)
            showDemoPaste = true
        }
    }

    @MainActor
    private func generateBucketPreviews() async {
        for bucket in appState.buckets {
            guard bucketPreviewSignoffs[bucket.id] == nil else { continue }
            isGeneratingBucketPreview[bucket.id] = true

            let outcome = await GenerationService.shared.generate(
                bucketId: bucket.id,
                profile: appState.profile,
                recentTexts: [],
                unhingedLevel: bucket.unhingedLevel,
                toneValue: bucket.toneValue,
                postfixMode: bucket.postfixMode,
                customInstructions: bucket.customInstructions,
                phraseList: bucket.phraseListJSON,
                ageGroup: appState.settings.generationAgeGroup
            )

            isGeneratingBucketPreview[bucket.id] = false

            switch outcome {
            case .success(let o):
                bucketPreviewSignoffs[bucket.id] = o.text
            case .providerFailed(let reason):
                bucketPreviewError[bucket.id] = reason
            case .usageLimitReached:
                bucketPreviewError[bucket.id] = "Free tier limit reached"
            }
        }
    }

    @MainActor
    private func regenerateBucketPreview(_ bucket: Bucket) async {
        isGeneratingBucketPreview[bucket.id] = true
        bucketPreviewError[bucket.id] = nil

        let outcome = await GenerationService.shared.generate(
            bucketId: bucket.id,
            profile: appState.profile,
            recentTexts: [],
            unhingedLevel: bucket.unhingedLevel,
            toneValue: bucket.toneValue,
            postfixMode: bucket.postfixMode,
            customInstructions: bucket.customInstructions,
            phraseList: bucket.phraseListJSON,
            ageGroup: appState.settings.generationAgeGroup
        )

        isGeneratingBucketPreview[bucket.id] = false

        switch outcome {
        case .success(let o):
            bucketPreviewSignoffs[bucket.id] = o.text
        case .providerFailed(let reason):
            bucketPreviewError[bucket.id] = reason
        case .usageLimitReached:
            bucketPreviewError[bucket.id] = "Free tier limit reached"
        }
    }
}

// MARK: - Onboarding Step Enum (5 steps per brand spec)

enum OnboardingStep: String, CaseIterable, Identifiable, Equatable {
    case welcome
    case profile
    case accessibility
    case inputMonitoring
    case bucketTour

    var id: String { rawValue }
    var index: Int {
        switch self {
        case .welcome:         return 0
        case .profile:         return 1
        case .accessibility:   return 2
        case .inputMonitoring: return 3
        case .bucketTour:      return 4
        }
    }

    var title: String {
        switch self {
        case .welcome:         return "Welcome"
        case .profile:         return "Profile"
        case .accessibility:   return "Accessibility"
        case .inputMonitoring: return "Shortcuts"
        case .bucketTour:      return "Buckets"
        }
    }

    var systemImage: String {
        switch self {
        case .welcome:         return "sparkles"
        case .profile:         return "person.crop.circle"
        case .accessibility:   return "cursorarrow.rays"
        case .inputMonitoring: return "keyboard"
        case .bucketTour:      return "square.grid.2x2"
        }
    }
}

// MARK: - Step Indicator

struct StepIndicatorView: View {
    let currentStep: OnboardingStep
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(step.index <= currentStep.index
                                ? Brand.amber(for: scheme)
                                : Color.primary.opacity(0.15))
                            .frame(width: 10, height: 10)
                        if step.index < currentStep.index {
                            Image(systemName: "checkmark")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    if step != OnboardingStep.allCases.last {
                        Rectangle()
                            .fill(step.index < currentStep.index
                                ? Brand.amber(for: scheme)
                                : Color.primary.opacity(0.15))
                            .frame(height: 2)
                            .frame(maxWidth: 40)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Brand.Semantic.surfaceBase(for: scheme))
    }
}

// MARK: - Step 1: Welcome (Animated signature writing itself)

struct WelcomeStepView: View {
    let onContinue: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var animateStroke = false
    @State private var showContent = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Animated signature mark - writes itself
            ZStack {
                // Draw the signature stroke as it animates
                SignatureStroke()
                    .trim(from: 0, to: animateStroke ? 1 : 0)
                    .stroke(
                        Brand.amber(for: scheme),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: 80, height: 36)
                    .animation(.easeInOut(duration: 1.2).delay(0.3), value: animateStroke)

                // Amber accent dot at end
                Circle()
                    .fill(Brand.amber(for: scheme))
                    .frame(width: 8, height: 8)
                    .offset(x: animateStroke ? 40 : -40, y: 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(1.5), value: animateStroke)
            }
            .onAppear {
                animateStroke = true
                withAnimation(.easeOut(duration: 0.6).delay(1.8)) {
                    showContent = true
                }
            }

            VStack(spacing: 12) {
                Text("Your Mac's neural engine")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Brand.Semantic.textPrimary(for: scheme))
                Text("can write your signoffs.")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Brand.Semantic.textPrimary(for: scheme))

                Text("Let's teach it your voice.")
                    .font(.title3)
                    .foregroundStyle(Brand.Semantic.textSecondary(for: scheme))
                    .padding(.top, 4)
            }
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 10)
            .multilineTextAlignment(.center)

            Text("Signoff runs entirely on-device using Apple's Foundation Models. "
                 + "It silently learns from the messages you send — across Mail, Messages, Slack, and more — "
                 + "so every generated signoff sounds like your best writing, not a template.")
                .font(.callout)
                .foregroundStyle(Brand.Semantic.textTertiary(for: scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 10)

            Spacer()

            // Privacy reassurance
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Brand.amber(for: scheme))
                Text("100% private. No cloud. No fallback phrases. Your voice stays on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .opacity(showContent ? 1 : 0)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
    }
}

// Animated signature stroke path
struct SignatureStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Signature-like flowing stroke
        path.move(to: CGPoint(x: w * 0.1, y: h * 0.6))
        path.addCurve(
            to: CGPoint(x: w * 0.3, y: h * 0.2),
            control1: CGPoint(x: w * 0.15, y: h * 0.3),
            control2: CGPoint(x: w * 0.25, y: h * 0.15)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: h * 0.55),
            control1: CGPoint(x: w * 0.38, y: h * 0.25),
            control2: CGPoint(x: w * 0.42, y: h * 0.45)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.7, y: h * 0.3),
            control1: CGPoint(x: w * 0.58, y: h * 0.65),
            control2: CGPoint(x: w * 0.62, y: h * 0.35)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.9, y: h * 0.7),
            control1: CGPoint(x: w * 0.78, y: h * 0.25),
            control2: CGPoint(x: w * 0.82, y: h * 0.6)
        )
        return path
    }
}

// MARK: - Step 2: Profile (Live voice preview: FMF vs generic)

struct ProfileStepView: View {
    @Binding var name: String
    @Binding var selfDescription: String
    @Binding var voicePreviewSignoff: String
    @Binding var isGeneratingVoicePreview: Bool
    let onGenerateVoicePreview: () async -> Void
    let onContinue: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("How do you sound?")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Brand.Semantic.textPrimary(for: scheme))
                    .padding(.top, 8)

                Text("Your self-description helps the neural engine match your voice — formality, rhythm, and vocabulary.")
                    .font(.callout)
                    .foregroundStyle(Brand.Semantic.textSecondary(for: scheme))
                    .fixedSize(horizontal: false, vertical: true)

                // Name field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name (optional)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    TextField("Your name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                }

                // Self-description with live preview
                VStack(alignment: .leading, spacing: 6) {
                    Text("Self-description")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    TextField("e.g. \"Concise, warm, direct. I use 'Thanks,' and 'On it.' No fluff.\"", text: $selfDescription, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                        .lineLimit(3...6)
                }

                // Live preview: With your voice vs Without
                LiveVoicePreview(
                    withVoiceSignoff: voicePreviewSignoff,
                    isGenerating: isGeneratingVoicePreview,
                    onGenerate: onGenerateVoicePreview
                )

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 16)
        }
    }
}

// Live preview showing FMF output (with voice) vs Generic (without)
struct LiveVoicePreview: View {
    let withVoiceSignoff: String
    let isGenerating: Bool
    let onGenerate: () async -> Void
    @Environment(\.colorScheme) private var scheme

    private var withoutVoiceSamples: [String] {
        ["Best regards,", "Sincerely,", "Thank you.", "Regards,"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Live preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                } else if withVoiceSignoff.isEmpty {
                    Button {
                        Task { await onGenerate() }
                    } label: {
                        Label("Generate preview", systemImage: "waveform")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Brand.amber(for: scheme))
                }
            }

            HStack(alignment: .top, spacing: 16) {
                // With your voice (FMF-generated)
                VStack(alignment: .leading, spacing: 8) {
                    Label("With your voice", systemImage: "waveform")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.amber(for: scheme))
                        .labelStyle(.titleAndIcon)

                    if isGenerating {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Brand.amber(for: scheme).opacity(0.1))
                            .frame(height: 50)
                            .overlay {
                                ProgressView()
                                    .controlSize(.small)
                            }
                    } else if !withVoiceSignoff.isEmpty {
                        Text(withVoiceSignoff)
                            .font(.system(size: 14, weight: .regular, design: .monospaced))
                            .kerning(0.5)
                            .foregroundStyle(Brand.Semantic.textPrimary(for: scheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Brand.amber(for: scheme).opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Brand.amber(for: scheme).opacity(0.3), lineWidth: 1)
                            )
                    } else {
                        Text("Describe your voice, then generate")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Brand.amber(for: scheme).opacity(0.1))
                            )
                    }
                }
                .frame(maxWidth: .infinity)

                // Without (generic)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Without", systemImage: "xmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.gray)
                        .labelStyle(.titleAndIcon)

                    Text(withoutVoiceSamples.randomElement() ?? "Best regards,")
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .kerning(0.5)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.03))
        )
        .padding(.horizontal, 4)
    }
}

// MARK: - Step 3: Accessibility Demo (Generate → Paste in fake field)

struct AccessibilityDemoStepView: View {
    @Binding var demoSignoff: String
    @Binding var isGenerating: Bool
    @Binding var showDemoPaste: Bool
    let onGenerateDemo: () async -> Void
    let onContinue: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 20) {
            Text("See it work")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Brand.Semantic.textPrimary(for: scheme))
                .padding(.top, 8)

            Text("Grant Accessibility, then generate a signoff and watch it paste at your cursor.")
                .font(.callout)
                .foregroundStyle(Brand.Semantic.textSecondary(for: scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)

            // Demo area
            VStack(spacing: 16) {
                if !isGenerating && demoSignoff.isEmpty {
                    Button {
                        Task { await onGenerateDemo() }
                    } label: {
                        Label("Generate Demo Signoff", systemImage: "signature")
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.amber(for: scheme))
                    .controlSize(.large)
                } else {
                    // Show generated signoff
                    if !demoSignoff.isEmpty {
                        Text(demoSignoff)
                            .font(.system(size: 15, weight: .regular, design: .monospaced))
                            .kerning(0.5)
                            .foregroundStyle(Brand.Semantic.textPrimary(for: scheme))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Brand.Semantic.surfaceElevated(for: scheme))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Brand.amber(for: scheme).opacity(0.3), lineWidth: 1)
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if isGenerating {
                        ProgressView("Drafting on-device…")
                            .controlSize(.small)
                            .foregroundStyle(.secondary)
                    }

                    // Fake text field showing paste
                    if showDemoPaste {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your message")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(alignment: .bottom, spacing: 8) {
                                let signoffView = Text(demoSignoff)
                                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                                    .kerning(0.5)
                                    .foregroundStyle(Brand.amber(for: scheme))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Thanks for the quick review!")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                    signoffView
                                }

                                // Animated cursor
                                CursorAnimationView()
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Brand.amber(for: scheme).opacity(0.5), lineWidth: 2)
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Brand.amber(for: scheme).opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Brand.amber(for: scheme).opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 4)

            Spacer()

            // Permission button if not granted
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility not granted")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("Grant in System Settings → Privacy & Security → Accessibility to enable paste-at-cursor.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Open Settings") {
                    let opts = ["AXTrustedCheckOptionPrompt": NSNumber(value: true)] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(opts)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.amber(for: scheme))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
    }
}

// Animated cursor for paste demo
struct CursorAnimationView: View {
    @State private var blink = true
    var body: some View {
        Rectangle()
            .fill(Brand.amber(for: .light))
            .frame(width: 2, height: 18)
            .opacity(blink ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    blink = false
                }
            }
    }
}

// MARK: - Step 4: Input Monitoring (Shortcut diagram with amber highlights)

struct InputMonitoringStepView: View {
    @Binding var inputMonitoringGranted: Bool
    let onGrantAction: () -> Void
    let onContinue: () -> Void
    @Environment(\.colorScheme) private var scheme

    private let shortcuts: [(key: String, label: String, icon: String)] = [
        ("⌃⌘1", "Professional", "briefcase.fill"),
        ("⌃⌘2", "Standard", "bubble.left.and.bubble.right.fill"),
        ("⌃⌘3", "Unhinged", "sparkles"),
        ("⌃⌘4", "Custom", "slider.horizontal.3"),
        ("⌃⌘5", "List", "list.bullet"),
        ("⌃⌘6", "Footer", "signature"),
    ]

    var body: some View {
        VStack(spacing: 20) {
            Text("Your global shortcuts")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Brand.Semantic.textPrimary(for: scheme))
                .padding(.top, 8)

            Text("Hold ⌃⌘ + a digit from any app to generate instantly. No popover needed.")
                .font(.callout)
                .foregroundStyle(Brand.Semantic.textSecondary(for: scheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)

            VStack(spacing: 10) {
                ForEach(shortcuts, id: \.key) { shortcut in
                    HStack(spacing: 14) {
                        Text(shortcut.key)
                            .font(.system(.callout, design: .monospaced).weight(.semibold))
                            .foregroundStyle(inputMonitoringGranted ? Brand.amber(for: scheme) : Color.secondary.opacity(0.55))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill((inputMonitoringGranted ? Brand.amber(for: scheme) : Color.gray).opacity(0.12))
                            )

                        Image(systemName: shortcut.icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(inputMonitoringGranted ? Brand.accent(for: shortcut.key, scheme: scheme) : .secondary.opacity(0.5))
                            .frame(width: 24)

                        Text(shortcut.label)
                            .font(.callout)
                            .foregroundStyle(inputMonitoringGranted ? Brand.Semantic.textPrimary(for: scheme) : Color.secondary.opacity(0.55))

                        Spacer()

                        if inputMonitoringGranted {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(.vertical, 8)

            if !inputMonitoringGranted {
                VStack(spacing: 10) {
                    Text("Input Monitoring enables these global chords.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)

                    Button("Grant Input Monitoring") {
                        onGrantAction()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.amber(for: scheme))
                    .controlSize(.large)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, 16)
            } else {
                Text("Enabled. Try ⌃⌘1 from any app now.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                    .padding(.top, 4)
            }

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Step 5: Bucket Tour (Horizontal scroll with live FMF)

struct BucketTourStepView: View {
    @Binding var bucketPreviewSignoffs: [String: String]
    @Binding var isGeneratingBucketPreview: [String: Bool]
    @Binding var bucketPreviewError: [String: String]
    let onContinue: () -> Void
    let onBack: () -> Void
    let onRegenerate: (Bucket) async -> Void
    @StateObject private var appState = AppState.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your five registers")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Brand.Semantic.textPrimary(for: scheme))
                .padding(.top, 8)

            Text("Each bucket is a different tone. Swipe to preview live generations — every signoff is drafted fresh by your Mac's neural engine.")
                .font(.callout)
                .foregroundStyle(Brand.Semantic.textSecondary(for: scheme))
                .fixedSize(horizontal: false, vertical: true)

            // Horizontal scroll of bucket cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(appState.buckets, id: \.id) { bucket in
                        BucketPreviewCard(
                            bucket: bucket,
                            signoff: bucketPreviewSignoffs[bucket.id],
                            isGenerating: isGeneratingBucketPreview[bucket.id] ?? false,
                            error: bucketPreviewError[bucket.id],
                            onRegenerate: { b in
                                await onRegenerate(b)
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 280)

            Spacer(minLength: 20)
        }
    }
}

// MARK: - Bucket Preview Card

struct BucketPreviewCard: View {
    let bucket: Bucket
    let signoff: String?
    let isGenerating: Bool
    let error: String?
    let onRegenerate: (Bucket) async -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Bucket header
            HStack(spacing: 10) {
                Image(systemName: bucket.iconSymbol)
                    .font(.title2.weight(.medium))
                    .frame(width: 32)
                    .foregroundStyle(Brand.accent(for: bucket.id, scheme: scheme))

                VStack(alignment: .leading, spacing: 2) {
                    Text(bucket.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Brand.Semantic.textPrimary(for: scheme))
                    Text(bucket.toneLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.lowercase)
                }
                Spacer()
            }

            // Signoff preview area
            ZStack(alignment: .topTrailing) {
                if isGenerating {
                    VStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Drafting…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 80)
                } else if let signoff = signoff, !signoff.isEmpty {
                    Text(signoff)
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .kerning(0.5)
                        .foregroundStyle(Brand.Semantic.textPrimary(for: scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Brand.Semantic.surfaceElevated(for: scheme))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Brand.Semantic.divider(for: scheme), lineWidth: Brand.Layout.hairline)
                        )
                } else if let error = error {
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title3)
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(minHeight: 80)
                    .padding(.horizontal, 12)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("Generating…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 80)
                }

                // Regenerate button
                if signoff != nil || error != nil {
                    Button(action: { Task { await onRegenerate(bucket) } }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(Circle().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .offset(x: -4, y: 4)
                }
            }

            // Tone description
            Text(bucketDescription(bucket.id))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 280, height: 260)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Brand.Semantic.surfaceElevated(for: scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Brand.Semantic.divider(for: scheme), lineWidth: Brand.Layout.hairline)
        )
    }

    private func bucketDescription(_ id: String) -> String {
        switch id {
        case "professional": return "Executive register — measured, formal, concise"
        case "standard": return "Conversational register — natural, warm, versatile"
        case "unhinged": return "Creative register — playful, unexpected, human"
        case "custom": return "Your rules — fully personalized voice"
        case "list": return "Collected calm — structured, organized"
        case "footer": return "Formal register — signed, complete, official"
        default: return ""
        }
    }
}

// MARK: - Onboarding Footer

struct OnboardingFooter: View {
    let currentStep: OnboardingStep
    let onBack: () -> Void
    let onContinue: () -> Void
    let onSkip: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            if currentStep.index > 0 {
                Button {
                    onBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .foregroundStyle(Brand.Semantic.textPrimary(for: scheme))
                .help("Go back to previous step")
            } else {
                Button("Skip All") {
                    onSkip()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Skip onboarding and configure later in Settings")
            }

            Spacer()

            Button {
                onContinue()
            } label: {
                HStack(spacing: 6) {
                    Text(currentStep.index == OnboardingStep.allCases.count - 1 ? "Get Started" : "Continue")
                        .font(.callout.weight(.semibold))
                    if currentStep.index < OnboardingStep.allCases.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.amber(for: scheme))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(Brand.Semantic.surfaceBase(for: scheme))
    }
}

// MARK: - Permission Row (kept for compatibility)

private struct PermissionRow: View {
    let title: String
    let description: String
    @Binding var isGranted: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "lock.shield")
                .font(.title3)
                .foregroundStyle(isGranted ? Color.green : Color.secondary.opacity(0.55))
                .frame(width: 22, height: 22)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Brand.Semantic.textPrimary(for: scheme))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(Brand.Semantic.textTertiary(for: scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if isGranted {
                Text("Granted")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.green.opacity(0.12))
                    )
            } else {
                Button("Grant Access", action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.amber(for: scheme))
                    .controlSize(.small)
                    .font(.caption)
                    .accessibilityHint("Opens System Settings to the \(title) privacy pane")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Brand.Layout.controlCornerRadius, style: .continuous)
                .fill(Brand.Semantic.surfaceElevated(for: scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Brand.Layout.controlCornerRadius, style: .continuous)
                .stroke(Brand.Semantic.divider(for: scheme), lineWidth: Brand.Layout.hairline)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) — \(isGranted ? "Granted" : "Not granted")")
        .accessibilityHint(description)
    }
}

#Preview {
    SetupOnboardingStep()
        .frame(width: 560, height: 540)
}

