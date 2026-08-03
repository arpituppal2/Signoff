import SwiftUI

/// Tiny status icon — success, caution, info, or failure.
/// Uses SF Symbols; adapts to Dynamic Type and accessibility settings.
public struct StatusSymbol: View {
    public enum Kind {
        case success, caution, info, failure
    }

    public let kind: Kind
    public let pointSize: CGFloat

    public init(_ kind: Kind, pointSize: CGFloat = 11) {
        self.kind = kind
        self.pointSize = pointSize
    }

    public var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: pointSize, weight: .semibold))
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }

    private var symbolName: String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .info:    return "info.circle.fill"
        case .failure: return "xmark.circle.fill"
        }
    }

    private var color: SwiftUI.Color {
        switch kind {
        case .success: return .green
        case .caution: return .orange
        case .info:    return .secondary
        case .failure: return .red
        }
    }
}
