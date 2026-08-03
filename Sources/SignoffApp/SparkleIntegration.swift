// SparkleIntegration.swift — replaced Sparkle 2 with proprietary UpdateChecker.
// Lightweight in-house update system: reads JSON appcast, downloads DMG,
// presents native update UI. No external dependencies.

import Foundation
import AppKit
import SignoffCore

/// Wraps `UpdateChecker` so the app can defer init until
/// applicationDidFinishLaunching and respond to notification-based triggers.
@MainActor
public final class SparkleIntegration {

    public static let shared = SparkleIntegration()
    private let checker = UpdateChecker.shared

    private init() {}

    /// Initialize background update checking. Idempotent; safe to call multiple times.
    public func startIfNeeded() {
        guard Bundle.main.bundleIdentifier == "com.signoff.app" else { return }
        guard hasShipReadyFeedURL() else {
            SignoffLogLogger(.persistence).info(
                "Update checker skipped — SUFeedURL is missing or REPLACE_ME"
            )
            return
        }
        // First launch: skip auto-check so onboarding isn't interrupted.
        let isFirstLaunch = !UserDefaults.standard.bool(forKey: hasRunBeforeKey)
        if isFirstLaunch {
            UserDefaults.standard.set(true, forKey: hasRunBeforeKey)
            SignoffLogLogger(.persistence).info("Update checker wired (first-launch check suppressed)")
            return
        }
        // Background check once per day.
        if checker.shouldCheckAutomatically {
            Task { await checker.checkForUpdates() }
        }
        SignoffLogLogger(.persistence).info("Update checker wired")
    }

    /// True when a real feed URL is configured (not placeholder).
    public var canCheckForUpdates: Bool { checker.isConfigured }

    /// User-initiated check from About / Help menu.
    public func checkForUpdates() {
        guard checker.isConfigured else {
            SignoffLogLogger(.persistence).info("Check for Updates skipped — no feed URL")
            return
        }
        Task {
            await checker.checkForUpdates()
            if let update = checker.updateAvailable {
                await MainActor.run {
                    presentUpdateAlert(update)
                }
            } else {
                await MainActor.run {
                    presentNoUpdateAlert()
                }
            }
        }
    }

    /// Open release notes / changelog.
    public func showWhatsNew() {
        checker.showWhatsNew()
    }

    // MARK: - UI

    private func presentUpdateAlert(_ update: UpdateChecker.UpdateInfo) {
        let alert = NSAlert()
        alert.messageText = "Signoff \(update.version) Available"
        alert.informativeText = "Version \(update.version) (build \(update.build)) is ready to download."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        if update.releaseNotesURL != nil {
            alert.addButton(withTitle: "Release Notes")
        }

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn: // Download
            Task {
                if let dmgURL = await checker.downloadUpdate(update) {
                    await MainActor.run {
                        checker.installUpdate(at: dmgURL)
                    }
                } else {
                    await MainActor.run {
                        presentDownloadError()
                    }
                }
            }
        case .alertThirdButtonReturn: // Release Notes
            checker.showWhatsNew()
        default:
            break
        }
    }

    private func presentNoUpdateAlert() {
        let alert = NSAlert()
        alert.messageText = "Signoff Is Up to Date"
        alert.informativeText = "You're running the latest version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentDownloadError() {
        let alert = NSAlert()
        alert.messageText = "Download Failed"
        alert.informativeText = "Could not download the update. Check your internet connection and try again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Helpers

    private let hasRunBeforeKey = "SignoffHasRunBefore"

    private func hasShipReadyFeedURL() -> Bool {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return false }
        if raw == "REPLACE_ME" || raw.hasPrefix("REPLACE_ME") { return false }
        return true
    }
}
