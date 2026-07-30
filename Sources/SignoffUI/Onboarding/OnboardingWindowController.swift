import AppKit
import SwiftUI
import SignoffCore

/// Multi-step first-launch window per brand spec (Section 6.4):
/// 1. Welcome — animated signature writing itself + neural engine pitch
/// 2. Profile — name + self-description + live voice preview
/// 3. Accessibility — demo: generate → paste in fake text field
/// 4. Input Monitoring — shortcut diagram with amber highlights
/// 5. Bucket Tour — horizontal scroll with live FMF generation per bucket
@MainActor
public final class OnboardingWindowController: NSWindowController {
    private var onComplete: (() -> Void)?

    public convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Welcome to Signoff"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.init(window: panel)
    }

    public func present(onComplete: @escaping () -> Void = {}) {
        self.onComplete = onComplete
        guard let panel = window as? NSPanel else { return }

        let step = SetupOnboardingStep()

        let hostingView = NSHostingView(rootView: step)
        panel.contentView = hostingView
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public override func close() {
        window?.close()
        onComplete = nil
    }
}
