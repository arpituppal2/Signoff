import Foundation
import AppKit

/// Proprietary lightweight update checker — replaces Sparkle 2.
/// Reads a JSON appcast from a feed URL, compares versions,
/// downloads the update DMG, and presents installation UI.
///
/// Appcast format (JSON):
/// {
///     "version": "1.0.1",
///     "build": "2",
///     "releaseNotesURL": "https://signoff.app/changelog",
///     "downloadURL": "https://signoff.app/Signoff-1.0.1.dmg",
///     "minimumOSVersion": "26.0"
/// }
@MainActor
public final class UpdateChecker: ObservableObject {
    public static let shared = UpdateChecker()

    @Published public private(set) var updateAvailable: UpdateInfo?
    @Published public private(set) var isChecking = false
    @Published public private(set) var isDownloading = false
    @Published public private(set) var downloadProgress: Double = 0

    public struct UpdateInfo: Sendable, Codable, Equatable {
        public let version: String
        public let build: String
        public let releaseNotesURL: String?
        public let downloadURL: String
        public let minimumOSVersion: String?

        public init(version: String, build: String, releaseNotesURL: String? = nil,
                    downloadURL: String, minimumOSVersion: String? = nil) {
            self.version = version
            self.build = build
            self.releaseNotesURL = releaseNotesURL
            self.downloadURL = downloadURL
            self.minimumOSVersion = minimumOSVersion
        }
    }

    private let session: URLSession
    private var downloadTask: URLSessionDownloadTask?
    private var hasRunBeforeKey = "SignoffHasRunBefore"
    private var lastCheckKey = "SignoffLastUpdateCheck"

    /// Feed URL from Info.plist (set via build.sh or defaults to GitHub releases).
    private var feedURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://signoff.app/appcast.json")!
    }

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Check for updates asynchronously. Publishes `updateAvailable` on success.
    public func checkForUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            let (data, response) = try await session.data(from: feedURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                SignoffLogLogger(.persistence).info("Update check failed: non-2xx response")
                return
            }
            let decoder = JSONDecoder()
            let feed = try decoder.decode(UpdateInfo.self, from: data)

            let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
            let currentBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

            // Compare versions: newer version or same version but newer build.
            let needsUpdate = feed.version.compare(currentVersion, options: .numeric) == .orderedDescending
                || (feed.version == currentVersion && feed.build.compare(currentBuild, options: .numeric) == .orderedDescending)

            if needsUpdate {
                self.updateAvailable = feed
                UserDefaults.standard.set(feed.version, forKey: "SignoffUpdateVersion")
                SignoffLogLogger(.persistence).info("Update available: \(feed.version) (\(feed.build))")
            } else {
                self.updateAvailable = nil
                SignoffLogLogger(.persistence).info("No update available (current: \(currentVersion) (\(currentBuild)))")
            }

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
        } catch {
            SignoffLogLogger(.persistence).debug("Update check failed: \(error.localizedDescription)")
        }
    }

    /// Download and prepare the update for installation.
    /// Returns the local file URL of the downloaded DMG, or nil on failure.
    public func downloadUpdate(_ update: UpdateInfo) async -> URL? {
        guard let url = URL(string: update.downloadURL) else { return nil }
        isDownloading = true
        downloadProgress = 0
        defer {
            isDownloading = false
            downloadProgress = 0
        }

        do {
            let (localURL, response) = try await session.download(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                SignoffLogLogger(.persistence).info("Update download failed: non-2xx response")
                return nil
            }
            // Move to a permanent location.
            let downloadsDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("SignoffUpdates", isDirectory: true)
            try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
            let destURL = downloadsDir.appendingPathComponent("Signoff-\(update.version).dmg")
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.moveItem(at: localURL, to: destURL)
            downloadProgress = 1.0
            SignoffLogLogger(.persistence).info("Update downloaded: \(destURL.path)")
            return destURL
        } catch {
            SignoffLogLogger(.persistence).debug("Update download failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Open the downloaded DMG in Finder for the user to install.
    public func installUpdate(at url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Open release notes in the browser.
    public func showWhatsNew() {
        let urlString = updateAvailable?.releaseNotesURL ?? "https://signoff.app/changelog"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Whether a background check should run (once per day).
    public var shouldCheckAutomatically: Bool {
        let lastCheck = UserDefaults.standard.double(forKey: lastCheckKey)
        guard lastCheck > 0 else { return true }
        let elapsed = Date().timeIntervalSince1970 - lastCheck
        return elapsed > 86400 // 24 hours
    }

    /// Whether the update system has a valid feed configured.
    public var isConfigured: Bool {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !raw.isEmpty && raw != "REPLACE_ME"
    }
}
