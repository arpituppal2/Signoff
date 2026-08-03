import AppKit
import SwiftUI
import SignoffCore

/// Captures a bucket hotkey chord via a local key-down monitor and reports
/// digit + modifier back to Settings → Shortcuts. Supports ⌃⌘1–4 and ⌥⌘1–4
/// (the two modifier families Signoff registers).
///
/// While recording, the Carbon event tap is temporarily suspended (without
/// flipping Pause shortcuts) so the local monitor can receive the chord.
public struct ShortcutRecorderView: View {
    public let currentDigitKey: String
    public let currentModifier: String
    public let onCommit: (_ digitKey: String, _ modifier: String) -> Void

    @StateObject private var session = RecorderSession()

    public init(currentDigitKey: String,
                currentModifier: String,
                onCommit: @escaping (_ digitKey: String, _ modifier: String) -> Void) {
        self.currentDigitKey = currentDigitKey
        self.currentModifier = currentModifier
        self.onCommit = onCommit
    }

    public var body: some View {
        Button {
            if session.isRecording {
                session.stop(resumeTap: true)
            } else {
                session.start { digit, modifier in
                    onCommit(digit, modifier)
                }
            }
        } label: {
            Text(session.isRecording ? "Type shortcut…" : displayString)
                .font(.body.monospaced())
                .foregroundStyle(session.isRecording ? Color.accentColor : .primary)
                .frame(minWidth: 88, alignment: .trailing)
        }
        .buttonStyle(.bordered)
        .help(session.isRecording
              ? "Press ⌃⌘ or ⌥⌘ plus a digit 1–4. Esc cancels."
              : "Click, then press a new shortcut")
        .accessibilityLabel(session.isRecording ? "Recording shortcut" : "Shortcut \(displayString)")
        .accessibilityHint(session.isRecording
                           ? "Press Control-Command or Option-Command and a digit from 1 to 4"
                           : "Activate to record a new shortcut")
        .onDisappear { session.stop(resumeTap: true) }
    }

    private var displayString: String {
        let mod = currentModifier == "optCmd" ? "⌥⌘" : "⌃⌘"
        return "\(mod)\(currentDigitKey)"
    }
}

/// Owns the AppKit local monitor so the CGEvent callback never captures a SwiftUI `View`.
@MainActor
private final class RecorderSession: ObservableObject {
    @Published var isRecording = false
    private var monitor: Any?
    private var didSuspendTap = false

    func start(onCommit: @escaping (String, String) -> Void) {
        endMonitorOnly()
        suspendTapIfNeeded()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                Task { @MainActor in self?.stop(resumeTap: true) }
                return nil
            }
            guard let digit = RecorderSession.digit(from: event) else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasCommand = flags.contains(.command)
            let hasControl = flags.contains(.control)
            let hasOption = flags.contains(.option)
            guard hasCommand, hasControl || hasOption else { return event }

            let modifier = (hasOption && !hasControl) ? "optCmd" : "cmdCtrl"
            Task { @MainActor in
                // Commit first; Settings' `applyShortcutBindings` re-registers.
                // `resumeTap: false` avoids a race that would reinstall old chords.
                onCommit(digit, modifier)
                self?.stop(resumeTap: false)
            }
            return nil
        }
    }

    func stop(resumeTap: Bool) {
        endMonitorOnly()
        isRecording = false
        if resumeTap {
            resumeTapIfNeeded()
        } else {
            // Commit path re-registers via AppState; drop the suspend flag.
            didSuspendTap = false
        }
    }

    private func endMonitorOnly() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func suspendTapIfNeeded() {
        let manager = ShortcutManager.shared
        guard !manager.isPaused else {
            didSuspendTap = false
            return
        }
        manager.suspendTapTemporarily()
        didSuspendTap = true
    }

    private func resumeTapIfNeeded() {
        guard didSuspendTap else { return }
        didSuspendTap = false
        guard !ShortcutManager.shared.isPaused else { return }
        Task { await AppState.shared.registerShortcutBindings() }
    }

    private static func digit(from event: NSEvent) -> String? {
        switch event.keyCode {
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        default:
            let chars = event.charactersIgnoringModifiers ?? ""
            guard chars.count == 1, let ch = chars.first, ("1"..."4").contains(ch) else {
                return nil
            }
            return String(ch)
        }
    }
}
