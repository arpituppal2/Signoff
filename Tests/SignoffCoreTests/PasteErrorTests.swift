import Testing
import Foundation
import AppKit
@testable import SignoffCore

/// Behavioral coverage for `PasteAutomation.paste(_:)` failure + clipboard
/// restore paths, plus the AppState CTA mapping. Accessibility is injected so
/// these do not require live AX / TCC.
@Suite(.serialized)
@MainActor
struct PasteErrorTests {

    // MARK: - Test isolation helpers

    private func withPasteboardSnapshot<T>(_ body: () async throws -> T) async rethrows -> T {
        // Skip the one-shot OS Accessibility prompt during unit tests.
        let priorPrompted = UserDefaults.standard.object(forKey: "signoff.axPrompted") as? Bool
        UserDefaults.standard.set(true, forKey: "signoff.axPrompted")
        let priorPasteboard = PasteboardSnapshot.capture(from: .general)

        let shared = PasteAutomation.shared
        let priorSharedAXCheck = shared.accessibilityTrustedCheck
        let priorSharedRestoreDelay = shared.pasteboardRestoreDelayNanoseconds
        let priorSharedOnSuccess = shared.onPasteSucceeded

        defer {
            shared.accessibilityTrustedCheck = priorSharedAXCheck
            shared.pasteboardRestoreDelayNanoseconds = priorSharedRestoreDelay
            shared.onPasteSucceeded = priorSharedOnSuccess
            priorPasteboard.restore(onto: .general)
            if let priorPrompted {
                UserDefaults.standard.set(priorPrompted, forKey: "signoff.axPrompted")
            } else {
                UserDefaults.standard.removeObject(forKey: "signoff.axPrompted")
            }
        }

        return try await body()
    }

    // MARK: - Tests

    @Test("Denied path throws accessibilityDenied without mutating pasteboard")
    func deniedPathThrowsAccessibilityDeniedWithoutMutatingPasteboard() async throws {
        try await withPasteboardSnapshot {
            let original = "user-clipboard-\(UUID().uuidString)"
            NSPasteboard.general.clearContents()
            #expect(NSPasteboard.general.setString(original, forType: .string) == true)

            let automation = PasteAutomation()
            automation.accessibilityTrustedCheck = { false }
            automation.pasteboardRestoreDelayNanoseconds = 0
            automation.onPasteSucceeded = { _ in }

            await #expect(throws: PasteError.accessibilityDenied) {
                try await automation.paste("Thanks so much.")
            }

            #expect(NSPasteboard.general.string(forType: .string) == original,
                "Denied path must not steal the user's clipboard")
            #expect(automation.isPermissionGranted == false)
        }
    }

    @Test("Trusted path restores prior pasteboard after paste")
    func trustedPathRestoresPriorPasteboardAfterPaste() async throws {
        try await withPasteboardSnapshot {
            let original = "prior-clipboard-\(UUID().uuidString)"
            NSPasteboard.general.clearContents()
            #expect(NSPasteboard.general.setString(original, forType: .string) == true)

            let automation = PasteAutomation()
            automation.accessibilityTrustedCheck = { true }
            automation.pasteboardRestoreDelayNanoseconds = 0
            automation.onPasteSucceeded = { _ in }

            try await automation.paste("Cheers — Signoff.")

            #expect(NSPasteboard.general.string(forType: .string) == original,
                "After steal-and-paste, prior clipboard contents must be restored")
            #expect(automation.isPermissionGranted == true)
        }
    }

    @Test("Pasteboard snapshot round trip preserves string payload")
    func pasteboardSnapshotRoundTripPreservesStringPayload() async throws {
        try await withPasteboardSnapshot {
            let marker = "snapshot-roundtrip-\(UUID().uuidString)"
            NSPasteboard.general.clearContents()
            #expect(NSPasteboard.general.setString(marker, forType: .string) == true)

            let snap = PasteboardSnapshot.capture(from: .general)
            NSPasteboard.general.clearContents()
            #expect(NSPasteboard.general.string(forType: .string) == nil)

            #expect(snap.restore(onto: .general) == true)
            #expect(NSPasteboard.general.string(forType: .string) == marker)
            #expect(snap.stringValue == marker)
        }
    }

    @Test("Pasteboard snapshot empty restore clears temporary contents")
    func pasteboardSnapshotEmptyRestoreClearsTemporaryContents() async throws {
        try await withPasteboardSnapshot {
            NSPasteboard.general.clearContents()
            let empty = PasteboardSnapshot.capture(from: .general)
            #expect(empty.items.isEmpty)

            #expect(NSPasteboard.general.setString("temporary-signoff", forType: .string) == true)
            #expect(empty.restore(onto: .general) == true)
            #expect(NSPasteboard.general.string(forType: .string) == nil,
                "Empty prior snapshot must clear the temporary sign-off")
        }
    }

    @Test("Pasteboard snapshot ignores non-restorable types")
    func pasteboardSnapshotIgnoresNonRestorableTypes() async throws {
        try await withPasteboardSnapshot {
            NSPasteboard.general.clearContents()
            let item = NSPasteboardItem()
            item.setString("keep-me", forType: .string)
            item.setString("file:///tmp/ignored", forType: .fileURL)
            #expect(NSPasteboard.general.writeObjects([item]) == true)

            let snap = PasteboardSnapshot.capture(from: .general)
            #expect(snap.stringValue == "keep-me")
            #expect(snap.items.first?[.fileURL] == nil,
                "fileURL must not enter the restorable snapshot")

            NSPasteboard.general.clearContents()
            #expect(snap.restore(onto: .general) == true)
            #expect(NSPasteboard.general.string(forType: .string) == "keep-me")
        }
    }

    /// Multi-type clipboard: steal-and-paste must restore string + RTF together,
    /// not just the plain-text representation.
    @Test("Pasteboard snapshot round trip preserves multiple types")
    func pasteboardSnapshotRoundTripPreservesMultipleTypes() async throws {
        try await withPasteboardSnapshot {
            let plain = "multi-type-\(UUID().uuidString)"
            let rtfData = Data("""
            {\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Helvetica;}}\\f0\\fs24 \(plain)}
            """.utf8)

            NSPasteboard.general.clearContents()
            let item = NSPasteboardItem()
            item.setString(plain, forType: .string)
            item.setData(rtfData, forType: .rtf)
            #expect(NSPasteboard.general.writeObjects([item]) == true)

            let snap = PasteboardSnapshot.capture(from: .general)
            #expect(snap.stringValue == plain)
            #expect(snap.rtfData == rtfData)

            NSPasteboard.general.clearContents()
            #expect(NSPasteboard.general.string(forType: .string) == nil)
            #expect(NSPasteboard.general.data(forType: .rtf) == nil)

            #expect(snap.restore(onto: .general) == true)
            #expect(NSPasteboard.general.string(forType: .string) == plain)
            #expect(NSPasteboard.general.data(forType: .rtf) == rtfData)
        }
    }

    @Test("Trusted path restores multi-type pasteboard after paste")
    func trustedPathRestoresMultiTypePasteboardAfterPaste() async throws {
        try await withPasteboardSnapshot {
            let plain = "prior-multi-\(UUID().uuidString)"
            let rtfData = Data("""
            {\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Helvetica;}}\\f0\\fs24 \(plain)}
            """.utf8)
            NSPasteboard.general.clearContents()
            let item = NSPasteboardItem()
            item.setString(plain, forType: .string)
            item.setData(rtfData, forType: .rtf)
            #expect(NSPasteboard.general.writeObjects([item]) == true)

            let automation = PasteAutomation()
            automation.accessibilityTrustedCheck = { true }
            automation.pasteboardRestoreDelayNanoseconds = 0
            automation.onPasteSucceeded = { _ in }

            try await automation.paste("Cheers — Signoff.")

            #expect(NSPasteboard.general.string(forType: .string) == plain)
            #expect(NSPasteboard.general.data(forType: .rtf) == rtfData,
                "Prior RTF payload must survive steal-and-paste restore")
        }
    }

    /// AppState CTA path: denied paste replaces generated text with the
    /// Accessibility CTA (not enum-equality theater).
    @Test("AppState commit paste denied fires accessibility CTA")
    func appStateCommitPasteDeniedFiresAccessibilityCTA() async throws {
        try await withPasteboardSnapshot {
            let shared = PasteAutomation.shared
            shared.accessibilityTrustedCheck = { false }
            shared.pasteboardRestoreDelayNanoseconds = 0
            shared.onPasteSucceeded = { _ in }

            let original = "cta-clipboard-\(UUID().uuidString)"
            NSPasteboard.general.clearContents()
            #expect(NSPasteboard.general.setString(original, forType: .string) == true)

            let state = AppState.preview
            state.generatedText = "Thanks for shipping this."

            let succeeded = await state.commitGeneratedPaste("Thanks for shipping this.")

            #expect(succeeded == false)
            #expect(state.generatedText == AppState.accessibilityDeniedCTA)
            #expect(state.generatedText?.localizedCaseInsensitiveContains("Accessibility") == true)
            #expect(NSPasteboard.general.string(forType: .string) == original,
                "AppState denied CTA path must not clobber the clipboard")
        }
    }

    /// Before the brand A11y explainer has been shown, denied AX must post
    /// `.signoffNeedsA11yExplainer` and throw — never steal the clipboard or
    /// fire the OS prompt.
    @Test("Denied without accessibility returns error")
    func deniedWithoutAccessibilityReturnsError() async throws {
        try await withPasteboardSnapshot {
            let original = "pre-explainer-\(UUID().uuidString)"
            NSPasteboard.general.clearContents()
            #expect(NSPasteboard.general.setString(original, forType: .string) == true)

            let automation = PasteAutomation()
            automation.accessibilityTrustedCheck = { false }
            automation.pasteboardRestoreDelayNanoseconds = 0
            automation.onPasteSucceeded = { _ in }

            await #expect(throws: PasteError.accessibilityDenied) {
                try await automation.paste("Thanks so much.")
            }

            #expect(NSPasteboard.general.string(forType: .string) == original)
        }
    }

    @Test("Accessibility denied CTA mentions system settings")
    func accessibilityDeniedCTAMentionsSystemSettings() {
        let cta = AppState.accessibilityDeniedCTA
        #expect(cta.localizedCaseInsensitiveContains("Accessibility"))
        #expect(
            cta.localizedCaseInsensitiveContains("System Settings")
            || cta.localizedCaseInsensitiveContains("Privacy")
        )
    }
}