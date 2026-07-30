// ErrorFixCard.swift — DX-EXP-7.
// Every error site surfaces an actionable FixCard instead of a generic toast.

import Foundation
import SwiftUI
import SignoffCore

/// Domain enumeration for error-to-fix mapping.
public enum SignoffFailure: Equatable, CaseIterable {
    case a11yDenied
    case inputMonitoringDenied
    case fmUnavailable
    case fallbackExhausted
    case rateLimited
    case storeCorrupt
    case storeInMemoryFallback

    public var title: String {
        switch self {
        case .a11yDenied:             return "Accessibility not granted"
        case .inputMonitoringDenied:  return "Input Monitoring not granted"
        case .fmUnavailable:          return "On-device AI not ready"
        case .fallbackExhausted:      return "Bundled phrases exhausted"
        case .rateLimited:            return "Rate limit reached"
        case .storeCorrupt:           return "Local store was reset"
        case .storeInMemoryFallback:  return "Local store unavailable"
        }
    }

    public var cause: String {
        switch self {
        case .a11yDenied:
            return "Signoff needs Accessibility to paste your signoff at the cursor without switching apps."
        case .inputMonitoringDenied:
            return "Global shortcuts (⌃⌘1–6) need Input Monitoring. This is separate from Accessibility."
        case .fmUnavailable:
            return "Your Mac's on-device model isn't ready yet. Signoff will draft from its private offline phrasebook until Apple Intelligence is available — still 100% on your Mac."
        case .fallbackExhausted:
            return "We de-duplicated against your last 50 phrases and ran out of fresh options."
        case .rateLimited:
            return "Per Apple HIG, AppIntents are rate-limited to 30 generations/hour for stability."
        case .storeCorrupt:
            return StoreRecovery.resetCorruptStore.userMessage
        case .storeInMemoryFallback:
            return StoreRecovery.inMemoryFallback.userMessage
        }
    }

    public var fixAction: FixAction {
        switch self {
        case .a11yDenied:
            return .openSystemSettings(scheme: AccessibilityAccess.systemSettingsURL.absoluteString)
        case .inputMonitoringDenied:
            return .openSystemSettings(scheme: InputMonitoringAccess.systemSettingsURL.absoluteString)
        case .fmUnavailable:
            return .message("Your Mac's AI system needs a moment. Try Generate again.")
        case .fallbackExhausted:
            return .openSettings(pane: .buckets)
        case .rateLimited:
            return .message("Try again in an hour.")
        case .storeCorrupt:
            return .message("A fresh store is already in use. Continue generating — previous local history may be gone.")
        case .storeInMemoryFallback:
            return .message("Quit and relaunch Signoff to retry the on-disk store. This session's changes won't be saved.")
        }
    }
}

public enum FixAction: Equatable {
    case openSystemSettings(scheme: String)
    case openSettings(pane: SettingsPane)
    case openURL(URL)
    case message(String)
}

/// Toolbar panes for the Settings scene.
public enum SettingsPane: String, Equatable, Hashable, CaseIterable, Identifiable, Sendable {
    case general
    case profile
    case buckets
    case shortcuts
    case privacy
    case advanced

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "General"
        case .profile: return "Profile"
        case .buckets: return "Buckets"
        case .shortcuts: return "Shortcuts"
        case .privacy: return "Privacy"
        case .advanced: return "Advanced"
        }
    }

    public var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .profile: return "person.crop.circle"
        case .buckets: return "square.stack.3d.up"
        case .shortcuts: return "keyboard"
        case .privacy: return "hand.raised.fill"
        case .advanced: return "gearshape.2"
        }
    }

    public static func resolve(_ raw: String) -> SettingsPane {
        if let pane = SettingsPane(rawValue: raw) { return pane }
        switch raw {
        case "account", "help": return .profile
        case "license": return .general
        case "history": return .privacy
        default: return .general
        }
    }
}

/// Branded card shown instead of a raw toast for SignoffFailure cases.
@MainActor
public struct ErrorFixCard: View {
    public let failure: SignoffFailure
    public let onAction: (FixAction) -> Void
    public let onDismiss: () -> Void

    public init(failure: SignoffFailure,
                onAction: @escaping (FixAction) -> Void,
                onDismiss: @escaping () -> Void) {
        self.failure = failure
        self.onAction = onAction
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(failure.title).font(.callout.weight(.semibold))
            }
            Text(failure.cause)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Dismiss") { onDismiss() }
                    .buttonStyle(.borderless)
                    .accessibilityHint("Dismiss this error card")
                Spacer()
                Button(actionLabel, action: { onAction(failure.fixAction) })
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Take the recommended fix for this error")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(failure.title). \(failure.cause)")
        .accessibilityHint("Use the action button to resolve this issue")
    }

    private var actionLabel: String {
        switch failure.fixAction {
        case .openSystemSettings:
            switch failure {
            case .fmUnavailable: return "Open Apple Intelligence"
            case .inputMonitoringDenied: return "Open Input Monitoring"
            case .a11yDenied: return "Open Accessibility"
            default: return "Open System Settings"
            }
        case .openSettings(let pane):
            switch pane {
            case .privacy: return "Open Privacy"
            case .buckets: return "Open Buckets"
            default: return "Open Settings"
            }
        case .openURL:            return "Open Link"
        case .message:            return "Got it"
        }
    }
}
