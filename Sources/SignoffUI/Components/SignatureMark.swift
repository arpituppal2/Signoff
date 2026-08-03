import SwiftUI

/// The animated pen-stroke "S" mark shown in the menu-bar header and help overlay.
public struct SignatureMark: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var strokeProgress: CGFloat = 0
    @State private var underlineProgress: CGFloat = 0

    let isGenerating: Bool
    let onAnimationComplete: (() -> Void)?

    public init(isGenerating: Bool = false, onAnimationComplete: (() -> Void)? = nil) {
        self.isGenerating = isGenerating
        self.onAnimationComplete = onAnimationComplete
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Brand.Layout.radiusM, style: .continuous)
                .fill(Brand.Surface.raised(for: scheme))
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.Layout.radiusM, style: .continuous)
                        .stroke(Brand.ember(for: scheme).opacity(0.35), lineWidth: Brand.Layout.hairline)
                )
                .frame(width: 36, height: 36)
                .shadow(
                    color: Brand.Shadow.card.color,
                    radius: Brand.Shadow.card.radius,
                    x: Brand.Shadow.card.x,
                    y: Brand.Shadow.card.y
                )

            PenStrokeShape(progress: strokeProgress)
                .stroke(
                    Brand.ember(for: scheme),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 24, height: 24)
                .shadow(color: Brand.ember(for: scheme).opacity(0.4), radius: 3, x: 0, y: 1)

            AmberUnderlineShape(progress: underlineProgress)
                .fill(
                    LinearGradient(
                        colors: [
                            Brand.ember(for: scheme).opacity(0),
                            Brand.ember(for: scheme),
                            Brand.ember(for: scheme).opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 28, height: 3)
                .offset(y: 8)
        }
        .accessibilityHidden(true)
        .onAppear { startAnimation() }
        .onChange(of: isGenerating) { _, newValue in
            if newValue { startAnimation() }
        }
    }

    private func startAnimation() {
        guard !reduceMotion else {
            strokeProgress = 1
            underlineProgress = 1
            onAnimationComplete?()
            return
        }

        strokeProgress = 0
        underlineProgress = 0

        withAnimation(Brand.Motion.safe(.spring(response: 0.5, dampingFraction: 0.7), reduceMotion: reduceMotion)) {
            strokeProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(Brand.Motion.safe(.easeOut(duration: 0.4), reduceMotion: reduceMotion)) {
                underlineProgress = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            onAnimationComplete?()
        }
    }
}

// MARK: - Supporting Shapes

private struct PenStrokeShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height

        path.move(to: CGPoint(x: width * 0.75, y: height * 0.15))
        path.addCurve(
            to: CGPoint(x: width * 0.25, y: height * 0.35),
            control1: CGPoint(x: width * 0.85, y: height * 0.05),
            control2: CGPoint(x: width * 0.35, y: height * 0.2)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.7, y: height * 0.65),
            control1: CGPoint(x: width * 0.1, y: height * 0.5),
            control2: CGPoint(x: width * 0.6, y: height * 0.55)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.25, y: height * 0.85),
            control1: CGPoint(x: width * 0.85, y: height * 0.8),
            control2: CGPoint(x: width * 0.4, y: height * 0.9)
        )

        let trimmed = path.trimmedPath(from: 0, to: progress)
        return trimmed
    }
}

private struct AmberUnderlineShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width * progress
        path.addRoundedRect(in: CGRect(x: 0, y: 0, width: width, height: rect.height), cornerSize: CGSize(width: 1.5, height: 1.5))
        return path
    }
}