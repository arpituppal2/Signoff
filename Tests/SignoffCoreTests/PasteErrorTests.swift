import XCTest
import AppKit
@testable import SignoffCore

/// Behavioral coverage for `PasteAutomation.paste(_:)` failure + clipboard
/// restore paths, plus the AppState CTA mapping. Accessibility is injected so
/// these do not require live AX / TCC.
@MainActor
final class PasteErrorTests: XCTestCase {

    private var priorPrompted: Bool?
    private var priorExplainer: Bool?
    private var priorPasteboard: PasteboardSnapshot!
    private var priorSharedAXCheck: (() -> Bool)?
    private var priorSharedRestoreDelay: UInt64?
    private var priorSharedOnSuccess: ((String) async -> Void)?

    override func setUp() async throws {
        try await super.setUp()
        priorPrompted = UserDefaults.standard.object(forKey: "signoff.axPrompted") as? Bool
        // Skip the one-shot OS Accessibility prompt during unit tests.
        UserDefaults.standard.set(true, forKey: "signoff.axPrompted")
        priorPasteboard = PasteboardSnapshot.capture(from: .general)

        let shared = PasteAutomation.shared
        priorSharedAXCheck = shared.accessibilityTrustedCheck
        priorSharedRestoreDelay = shared.pasteboardRestoreDelayNanoseconds
        priorSharedOnSuccess = shared.onPasteSucceeded
    }

    override func tearDown() async throws {
        let shared = PasteAutomation.shared
        if let priorSharedAXCheck {
            shared.accessibilityTrustedCheck = priorSharedAXCheck
        }
        if let priorSharedRestoreDelay {
            shared.pasteboardRestoreDelayNanoseconds = priorSharedRestoreDelay
        }
        if let priorSharedOnSuccess {
            shared.onPasteSucceeded = priorSharedOnSuccess
        }

        priorPasteboard.restore(onto: .general)
        if let priorPrompted {
            UserDefaults.standard.set(priorPrompted, forKey: "signoff.axPrompted")
        } else {
            UserDefaults.standard.removeObject(forKey: "signoff.axPrompted")
        }
        try await super.tearDown()
    }

    func testDeniedPathThrowsAccessibilityDeniedWithoutMutatingPasteboard() async {
        let original = "user-clipboard-\(UUID().uuidString)"
        NSPasteboard.general.clearContents()
        XCTAssertTrue(NSPasteboard.general.setString(original, forType: .string))

        let automation = PasteAutomation()
        automation.accessibilityTrustedCheck = { false }
        automation.pasteboardRestoreDelayNanoseconds = 0
        automation.onPasteSucceeded = { _ in }

        do {
            try await automation.paste("Thanks so much.")
            XCTFail("Expected PasteError.accessibilityDenied when AX is not trusted")
        } catch PasteError.accessibilityDenied {
            // Expected — AppState maps this to the Accessibility CTA.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), original,
                       "Denied path must not steal the user's clipboard")
        XCTAssertFalse(automation.isPermissionGranted)
    }

    func testTrustedPathRestoresPriorPasteboardAfterPaste() async throws {
        let original = "prior-clipboard-\(UUID().uuidString)"
        NSPasteboard.general.clearContents()
        XCTAssertTrue(NSPasteboard.general.setString(original, forType: .string))

        let automation = PasteAutomation()
        automation.accessibilityTrustedCheck = { true }
        automation.pasteboardRestoreDelayNanoseconds = 0
        automation.onPasteSucceeded = { _ in }

        try await automation.paste("Cheers — Signoff.")

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), original,
                       "After steal-and-paste, prior clipboard contents must be restored")
        XCTAssertTrue(automation.isPermissionGranted)
    }

    func testPasteboardSnapshotRoundTripPreservesStringPayload() {
        let marker = "snapshot-roundtrip-\(UUID().uuidString)"
        NSPasteboard.general.clearContents()
        XCTAssertTrue(NSPasteboard.general.setString(marker, forType: .string))

        let snap = PasteboardSnapshot.capture(from: .general)
        NSPasteboard.general.clearContents()
        XCTAssertNil(NSPasteboard.general.string(forType: .string))

        XCTAssertTrue(snap.restore(onto: .general))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), marker)
        XCTAssertEqual(snap.stringValue, marker)
    }

    func testPasteboardSnapshotEmptyRestoreClearsTemporaryContents() {
        NSPasteboard.general.clearContents()
        let empty = PasteboardSnapshot.capture(from: .general)
        XCTAssertTrue(empty.items.isEmpty)

        XCTAssertTrue(NSPasteboard.general.setString("temporary-signoff", forType: .string))
        XCTAssertTrue(empty.restore(onto: .general))
        XCTAssertNil(NSPasteboard.general.string(forType: .string),
                     "Empty prior snapshot must clear the temporary sign-off")
    }

    func testPasteboardSnapshotIgnoresNonRestorableTypes() {
        NSPasteboard.general.clearContents()
        let item = NSPasteboardItem()
        item.setString("keep-me", forType: .string)
        item.setString("file:///tmp/ignored", forType: .fileURL)
        XCTAssertTrue(NSPasteboard.general.writeObjects([item]))

        let snap = PasteboardSnapshot.capture(from: .general)
        XCTAssertEqual(snap.stringValue, "keep-me")
        XCTAssertNil(snap.items.first?[.fileURL],
                     "fileURL must not enter the restorable snapshot")

        NSPasteboard.general.clearContents()
        XCTAssertTrue(snap.restore(onto: .general))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "keep-me")
    }

    /// Multi-type clipboard: steal-and-paste must restore string + RTF together,
    /// not just the plain-text representation.
    func testPasteboardSnapshotRoundTripPreservesMultipleTypes() {
        let plain = "multi-type-\(UUID().uuidString)"
        let rtfData = Data("""
        {\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Helvetica;}}\\f0\\fs24 \(plain)}
        """.utf8)

        NSPasteboard.general.clearContents()
        let item = NSPasteboardItem()
        item.setString(plain, forType: .string)
        item.setData(rtfData, forType: .rtf)
        XCTAssertTrue(NSPasteboard.general.writeObjects([item]))

        let snap = PasteboardSnapshot.capture(from: .general)
        XCTAssertEqual(snap.stringValue, plain)
        XCTAssertEqual(snap.rtfData, rtfData)

        NSPasteboard.general.clearContents()
        XCTAssertNil(NSPasteboard.general.string(forType: .string))
        XCTAssertNil(NSPasteboard.general.data(forType: .rtf))

        XCTAssertTrue(snap.restore(onto: .general))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), plain)
        XCTAssertEqual(NSPasteboard.general.data(forType: .rtf), rtfData)
    }

    func testTrustedPathRestoresMultiTypePasteboardAfterPaste() async throws {
        let plain = "prior-multi-\(UUID().uuidString)"
        let rtfData = Data("""
        {\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 Helvetica;}}\\f0\\fs24 \(plain)}
        """.utf8)
        NSPasteboard.general.clearContents()
        let item = NSPasteboardItem()
        item.setString(plain, forType: .string)
        item.setData(rtfData, forType: .rtf)
        XCTAssertTrue(NSPasteboard.general.writeObjects([item]))

        let automation = PasteAutomation()
        automation.accessibilityTrustedCheck = { true }
        automation.pasteboardRestoreDelayNanoseconds = 0
        automation.onPasteSucceeded = { _ in }

        try await automation.paste("Cheers — Signoff.")

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), plain)
        XCTAssertEqual(NSPasteboard.general.data(forType: .rtf), rtfData,
                       "Prior RTF payload must survive steal-and-paste restore")
    }

    /// AppState CTA path: denied paste replaces generated text with the
    /// Accessibility CTA (not enum-equality theater).
    func testAppStateCommitPasteDeniedFiresAccessibilityCTA() async {
        let shared = PasteAutomation.shared
        shared.accessibilityTrustedCheck = { false }
        shared.pasteboardRestoreDelayNanoseconds = 0
        shared.onPasteSucceeded = { _ in }

        let original = "cta-clipboard-\(UUID().uuidString)"
        NSPasteboard.general.clearContents()
        XCTAssertTrue(NSPasteboard.general.setString(original, forType: .string))

        let state = AppState.preview
        state.generatedText = "Thanks for shipping this."

        let succeeded = await state.commitGeneratedPaste("Thanks for shipping this.")

        XCTAssertFalse(succeeded)
        XCTAssertEqual(state.generatedText, AppState.accessibilityDeniedCTA)
        XCTAssertTrue(state.generatedText?.localizedCaseInsensitiveContains("Accessibility") == true)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), original,
                       "AppState denied CTA path must not clobber the clipboard")
    }

    /// Before the brand A11y explainer has been shown, denied AX must post
    /// `.signoffNeedsA11yExplainer` and throw — never steal the clipboard or
    /// fire the OS prompt.
    func testDeniedWithoutAccessibilityReturnsError() async {
        let original = "pre-explainer-\(UUID().uuidString)"
        NSPasteboard.general.clearContents()
        XCTAssertTrue(NSPasteboard.general.setString(original, forType: .string))

        let automation = PasteAutomation()
        automation.accessibilityTrustedCheck = { false }
        automation.pasteboardRestoreDelayNanoseconds = 0
        automation.onPasteSucceeded = { _ in }

        do {
            try await automation.paste("Thanks so much.")
            XCTFail("Expected PasteError.accessibilityDenied")
        } catch PasteError.accessibilityDenied {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), original)
    }

    func testAccessibilityDeniedCTAMentionsSystemSettings() {
        let cta = AppState.accessibilityDeniedCTA
        XCTAssertTrue(cta.localizedCaseInsensitiveContains("Accessibility"))
        XCTAssertTrue(cta.localizedCaseInsensitiveContains("System Settings")
                      || cta.localizedCaseInsensitiveContains("Privacy"))
    }
}
