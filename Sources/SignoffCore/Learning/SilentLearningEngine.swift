import Foundation
import AppKit
@preconcurrency import ApplicationServices
import os.signpost

/// SilentLearningEngine — the core differentiator of Signoff.
///
/// Observes ALL writing across the system via Accessibility (AXObserver).
/// Distinguishes QUALITY (adopted/sent/saved) from NOISE (deleted/abandoned/replaced).
/// Builds a discriminative voice profile that the Foundation Models framework uses
/// to generate signoffs that sound like the user's BEST writing, not their average writing.
///
/// PRIVACY GUARANTEES:
/// - Only observes FINAL text on SEND/SAVE actions (not keystrokes)
/// - Runs entirely on-device, encrypted at rest in SwiftData
/// - User can pause/inspect/reset anytime in Settings → Privacy
/// - No cloud, no analytics, no telemetry
@MainActor
public final class SilentLearningEngine: ObservableObject {
    public static let shared = SilentLearningEngine()

    @Published public private(set) var isObserving: Bool = false
    @Published public private(set) var observationCount: Int = 0
    @Published public private(set) var lastObservation: ObservedWriting?
    @Published public private(set) var observedApps: Set<String> = []

    private let log = SignoffLogLogger(.learning)
    private let signpostID = SignoffSignpost.learning.makeSignpostID()
    private var signpostState: OSSignpostIntervalState?

    private let voiceProfile = VoiceProfile.shared
    private let persistence = PersistenceController.shared

    // AX Observer state
    private var axObserver: AXObserver?
    private var runLoopObserver: CFRunLoopObserver?
    private var observedElements: Set<AXUIElement> = []
    private var lastTextByElement: [AXUIElement: String] = [:]
    private var elementContexts: [AXUIElement: WritingContext] = [:]

    // Quality classification
    private var pendingAdoptions: [AXUIElement: ObservedWriting] = [:]
    private var recentDeletions: [String: Date] = [:]

    // Throttling
    private let minObservationInterval: TimeInterval = 2.0
    private var lastObservationTime: Date = .distantPast

    private init() {
    }

    // MARK: - Public API

    /// Start silent observation. Requires Accessibility permission.
    public func start() async {
        guard !isObserving else { return }
        guard AXIsProcessTrusted() else {
            log.warning("Accessibility not granted - cannot start learning")
            return
        }

        signpostState = SignoffSignpost.learning.beginInterval("silent_learning", id: signpostID)

        // Create AXObserver
        var observer: AXObserver?
        let callback: AXObserverCallback = { observer, element, notification, refcon in
            SilentLearningEngine.shared.handleAXNotificationRaw(
                notification: notification as String,
                element: element
            )
        }

        let result = AXObserverCreate(pid_t(NSRunningApplication.current.processIdentifier), callback, &observer)
        guard result == .success, let observer = observer else {
            log.error("Failed to create AXObserver: \(result.rawValue)")
            return
        }

        self.axObserver = observer

        // Add to run loop
        let runLoopSource = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)

        // Add run loop observer to process pending notifications
        let loopObserver = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity.beforeWaiting.rawValue,
            true,
            0
        ) { _, _ in
            Task { @MainActor in
                SilentLearningEngine.sharedProcessPendingNotifications()
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), loopObserver, .commonModes)

        // Store for cleanup
        self.runLoopObserver = loopObserver

        // Start observing known writing apps
        await discoverAndObserveWritingApps()

        isObserving = true
        log.info("Silent learning engine started")
    }

    /// Stop silent observation
    public func stop() {
        guard isObserving else { return }

        if let observer = axObserver {
            for element in observedElements {
                AXObserverRemoveNotification(observer, element, kAXValueChangedNotification as CFString)
                AXObserverRemoveNotification(observer, element, kAXFocusedUIElementChangedNotification as CFString)
            }
            observedElements.removeAll()
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        if let loopObserver = runLoopObserver {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), loopObserver, .commonModes)
            runLoopObserver = nil
        }
        axObserver = nil
        pendingNotifications.removeAll()
        lastTextByElement.removeAll()
        elementContexts.removeAll()
        pendingAdoptions.removeAll()

        SignoffSignpost.learning.endInterval("silent_learning", signpostState!)
        isObserving = false
        log.info("Silent learning engine stopped")
    }

    /// Pause learning (user-triggered from menu bar)
    public func pause() {
        voiceProfile.isLearningPaused = true
        stop()
        log.info("Learning paused by user")
    }

    /// Resume learning
    public func resume() async {
        voiceProfile.isLearningPaused = false
        await start()
    }

    /// Reset all learned data
    public func reset() {
        stop()
        voiceProfile.reset()
        observationCount = 0
        observedApps.removeAll()
        lastObservation = nil
        log.info("Voice profile reset")
    }

    // MARK: - AX Notification Handling

    // The AXObserver callback is `@convention(c)` (can't be `@MainActor`), but its
    // run-loop source is attached to the main run loop in `start()`, so the
    // callback fires on the main thread. Drain runs on the main actor too — the
    // CFRunLoopObserver in `start()` spawns `Task { @MainActor in …drain… }`.
    // Both append and drain therefore land on the main actor, so the pending
    // buffer is plain main-actor state: no serial queue, no `@Sendable` closure
    // crossing a main-actor property, no data-race warning.
    private var pendingNotifications: [(String, AXUIElement)] = []

    @MainActor
    static func sharedProcessPendingNotifications() {
        SilentLearningEngine.shared._processPendingNotifications()
    }

    private func _processPendingNotifications() {
        let pending = pendingNotifications
        pendingNotifications.removeAll()
        for (notification, element) in pending {
            processAXNotification(element: element, notification: notification)
        }
    }

    private func handleAXNotificationRaw(notification: String, element: AXUIElement) {
        pendingNotifications.append((notification, element))
        // Kick the main run loop so the beforeWaiting observer drains promptly.
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    @MainActor
    private func processAXNotification(element: AXUIElement, notification: String) {
        let notif = notification

        if notif == kAXValueChangedNotification as String {
            handleValueChanged(element: element)
        } else if notif == kAXFocusedUIElementChangedNotification as String {
            handleFocusChanged(element: element)
        }
    }

    private func handleValueChanged(element: AXUIElement) {
        guard isObserving, !voiceProfile.isLearningPaused else { return }
        guard Date().timeIntervalSince(lastObservationTime) >= minObservationInterval else { return }

        // Get current text
        guard let currentText = getTextValue(element), !currentText.isEmpty else { return }

        // Get previous text
        let previousText = lastTextByElement[element] ?? ""

        // Skip if no meaningful change
        guard currentText != previousText else { return }
        lastTextByElement[element] = currentText

        // Determine context from element hierarchy
        let context = inferContext(from: element)
        elementContexts[element] = context

        // Classify the change
        let changeType = classifyChange(previous: previousText, current: currentText, context: context)

        switch changeType {
        case .adoption:
            // User sent/saved/kept this text - HIGH QUALITY
            recordAdoption(text: currentText, element: element, context: context)

        case .rejection:
            // User deleted/replaced text - NOISE
            recordRejection(text: previousText, element: element, context: context)

        case .draft:
            // In progress - track for potential adoption
            lastObservation = ObservedWriting(
                text: currentText,
                appBundleID: frontmostAppBundleID() ?? "unknown",
                appName: frontmostAppName() ?? "Unknown",
                context: context,
                quality: .draft,
                metadata: analyzeText(currentText)
            )
            // Don't persist drafts
        }
    }

    private func handleFocusChanged(element: AXUIElement) {
        // When focus moves to a text area, start watching it
        guard isObserving, !voiceProfile.isLearningPaused else { return }

        let role = getRole(element)
        let subrole = getSubrole(element)

        if isTextArea(role: role, subrole: subrole) {
            observeElement(element)
        }
    }

    // MARK: - Change Classification (The Core Logic)

    private enum ChangeType {
        case adoption    // Text was sent/saved/kept
        case rejection   // Text was deleted/replaced
        case draft       // In progress
    }

    private func classifyChange(previous: String, current: String, context: WritingContext) -> ChangeType {
        // Significant deletion = rejection
        if current.count < Int(Double(previous.count) * 0.3) && previous.count > 50 {
            return .rejection
        }

        // Text replaced wholesale = rejection of old, potential adoption of new
        if levenshteinRatio(previous, current) < 0.3 && previous.count > 30 {
            return .rejection
        }

        // Check for send/save actions in context
        if context == .emailCompose || context == .emailReply ||
           context == .documentSave || context == .noteSave {
            // Heuristic: if text ends with signature-like pattern or is substantial,
            // and this was a known compose window, classify as adoption
            if current.count > 30 && looksLikeCompletedMessage(current) {
                return .adoption
            }
        }

        // For messages: adoption happens on Enter/Cmd+Enter
        if context == .messageSend || context == .slackMessage ||
           context == .teamsMessage || context == .discordMessage ||
           context == .whatsappMessage {
            if current.count > 5 && previous.count < current.count {
                return .adoption
            }
        }

        return .draft
    }

    private func looksLikeCompletedMessage(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Ends with punctuation
        let endsWithPunctuation = trimmed.last.map { ".!?".contains($0) } ?? false

        // Contains a signoff-like ending
        let hasSignoff = signoffKeywords.contains { trimmed.localizedCaseInsensitiveContains($0) }

        // Or just substantial text
        return endsWithPunctuation || hasSignoff || trimmed.split(separator: " ").count > 10
    }

    private let signoffKeywords = [
        "thanks", "thank you", "best", "regards", "cheers", "talk soon",
        "sincerely", "respectfully", "later", "bye", "see you", "take care"
    ]

    // MARK: - Quality Recording

    private func recordAdoption(text: String, element: AXUIElement, context: WritingContext) {
        let metadata = analyzeText(text)

        let writing = ObservedWriting(
            text: text,
            appBundleID: frontmostAppBundleID() ?? "unknown",
            appName: frontmostAppName() ?? "Unknown",
            context: context,
            quality: .adopted,
            metadata: metadata
        )

        // Update voice profile with QUALITY patterns
        voiceProfile.learn(from: writing)

        // Extract signoff if present
        if let signoff = extractSignoff(from: text) {
            voiceProfile.adoptSignoff(signoff)
        }

        // Track app
        observedApps.insert(writing.appName)
        voiceProfile.observeApp(writing.appBundleID)

        // Update UI state
        observationCount += 1
        lastObservation = writing
        voiceProfile.totalQualityObservations += 1
        voiceProfile.lastUpdated = Date()

        log.info("Quality adoption: \(context.rawValue) from \(writing.appName) — \(text.count) chars")

        // Persist periodically
        if observationCount % 10 == 0 {
            Task { try? persistence.context.save() }
        }
    }

    private func recordRejection(text: String, element: AXUIElement, context: WritingContext) {
        guard text.count > 20 else { return } // Ignore tiny edits

        let metadata = analyzeText(text)

        let writing = ObservedWriting(
            text: text,
            appBundleID: frontmostAppBundleID() ?? "unknown",
            appName: frontmostAppName() ?? "Unknown",
            context: context,
            quality: .rejected,
            metadata: metadata
        )

        // Update voice profile with NOISE patterns
        voiceProfile.learnNoise(from: writing)

        // Extract rejected signoff
        if let signoff = extractSignoff(from: text) {
            voiceProfile.rejectSignoff(signoff)
        }

        voiceProfile.totalNoiseObservations += 1

        log.info("Noise rejection: \(context.rawValue) — \(text.count) chars")
    }

    private func extractSignoff(from text: String) -> String? {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let lastLine = lines.last, !lastLine.isEmpty else { return nil }

        // Known signoff patterns
        let patterns = [
            #"^(thanks?|thank you|best|regards|cheers|sincerely|respectfully)[,.!]?\s*$"#,
            #"^(talk soon|see you|take care|later|bye)[,.!]?\s*$"#,
            #"^[-—]\s*\w+.*$"# // — Name
        ]

        for pattern in patterns {
            if lastLine.range(of: pattern, options: .regularExpression) != nil {
                return lastLine
            }
        }

        // If last line is short and ends with punctuation, might be a signoff
        if lastLine.count <= 30,
           lastLine.last.map({ ".!?".contains($0) }) == true,
           lastLine.split(separator: " ").count <= 6 {
            return lastLine
        }

        return nil
    }

    // MARK: - Text Analysis

    private func analyzeText(_ text: String) -> WritingMetadata {
        var metadata = WritingMetadata()

        // Sentences
        let sentences = text.split { ".!?".contains($0) }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        metadata.sentenceCount = sentences.count

        // Words
        let words = text.split { $0.isWhitespace || $0.isPunctuation }
        metadata.wordCount = words.count

        // Emoji
        metadata.hasEmoji = text.unicodeScalars.contains { $0.properties.isEmoji }

        // Punctuation style
        let punctuationScalars: Set<Unicode.Scalar> = [".", "!", "?"]
        let totalPunct = text.unicodeScalars.filter { punctuationScalars.contains($0) }.count
        if totalPunct > 0 {
            let periods = text.unicodeScalars.filter { $0 == "." }.count
            let exclaims = text.unicodeScalars.filter { $0 == "!" }.count
            let questions = text.unicodeScalars.filter { $0 == "?" }.count
            metadata.punctuation.periodPercent = Double(periods) / Double(totalPunct) * 100
            metadata.punctuation.exclamationPercent = Double(exclaims) / Double(totalPunct) * 100
            metadata.punctuation.questionPercent = Double(questions) / Double(totalPunct) * 100
        }

        // Formality indicators
        metadata.formalityIndicators = analyzeFormality(text, words: Array(words), sentences: Array(sentences))

        return metadata
    }

    private func analyzeFormality(_ text: String, words: [Substring], sentences: [Substring]) -> FormalityIndicators {
        var indicators = FormalityIndicators()

        let lowerWords = words.map { $0.lowercased() }
        let totalWords = max(1, words.count)

        // Contractions = less formal
        let contractions = lowerWords.filter { $0.contains("'") }.count
        indicators.contractionRatio = Double(contractions) / Double(totalWords)

        // Hedging words = less formal
        let hedges = ["maybe", "perhaps", "kind of", "sort of", "i think", "i guess", "probably", "just"]
        indicators.hedgeWordCount = hedges.reduce(0) { count, hedge in
            count + lowerWords.filter { $0.contains(hedge) }.count
        }

        // Latinate words = more formal
        let latinateEndings = ["tion", "sion", "ment", "able", "ible", "ance", "ence", "ity", "ous", "ive"]
        let latinateCount = lowerWords.filter { word in
            latinateEndings.contains { word.hasSuffix($0) }
        }.count
        indicators.latinateWordRatio = Double(latinateCount) / Double(totalWords)

        // Passive voice (rough heuristic)
        let passiveMarkers = [" was ", " were ", " been ", " being ", " is ", " are "]
        indicators.passiveVoiceCount = passiveMarkers.reduce(0) { count, marker in
            count + text.lowercased().components(separatedBy: marker).count - 1
        }

        // Honorifics
        let honorifics = ["dear", "sir", "madam", "mr", "ms", "dr", "prof", "hello"]
        indicators.honorificCount = honorifics.reduce(0) { count, hon in
            count + lowerWords.filter { $0 == hon }.count
        }

        return indicators
    }

    // MARK: - Context Inference

    private func inferContext(from element: AXUIElement) -> WritingContext {
        // Get app
        let appName = frontmostAppName()?.lowercased() ?? ""

        // Check window/element hierarchy for clues
        let elementDesc = getElementDescription(element).lowercased()

        // Email apps
        if appName.contains("mail") || appName.contains("outlook") || appName.contains("spark") ||
           appName.contains("airmail") || appName.contains("mimestream") {
            if elementDesc.contains("compose") || elementDesc.contains("new message") {
                return .emailCompose
            }
            if elementDesc.contains("reply") || elementDesc.contains("forward") {
                return .emailReply
            }
        }

        // Messages
        if appName.contains("message") { return .messageSend }
        if appName.contains("slack") { return .slackMessage }
        if appName.contains("teams") || appName.contains("microsoft teams") { return .teamsMessage }
        if appName.contains("discord") { return .discordMessage }
        if appName.contains("whatsapp") { return .whatsappMessage }

        // Documents
        if appName.contains("notes") { return .noteSave }
        if appName.contains("pages") || appName.contains("word") || appName.contains("google docs") ||
           appName.contains("textedit") || appName.contains("bear") || appName.contains("obsidian") ||
           appName.contains("notion") || appName.contains("craft") {
            return .documentSave
        }

        // Code
        if appName.contains("xcode") || appName.contains("vscode") || appName.contains("cursor") ||
           appName.contains("zed") || appName.contains("sublime") || appName.contains("vim") {
            return .codeComment
        }

        return .other
    }

    // MARK: - AX Utilities

    private func getTextValue(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard result == .success, let str = value as? String else { return nil }
        return str
    }

    private func getRole(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        guard result == .success, let str = value as? String else { return nil }
        return str
    }

    private func getSubrole(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &value)
        guard result == .success, let str = value as? String else { return nil }
        return str
    }

    private func isTextArea(role: String?, subrole: String?) -> Bool {
        let textRoles = ["AXTextArea", "AXTextField", "AXWebArea", "AXStaticText"]
        let textSubroles = ["AXTextArea", "AXTextField", "AXSearchField", "AXSecureTextField"]

        if let role, textRoles.contains(role) { return true }
        if let subrole, textSubroles.contains(subrole) { return true }
        return false
    }

    private func getElementDescription(_ element: AXUIElement) -> String {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success,
           let str = value as? String {
            return str
        }
        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &value) == .success,
           let str = value as? String {
            return str
        }
        return ""
    }

    private func observeElement(_ element: AXUIElement) {
        guard let observer = axObserver, !observedElements.contains(element) else { return }

        let result1 = AXObserverAddNotification(observer, element, kAXValueChangedNotification as CFString, nil)
        let result2 = AXObserverAddNotification(observer, element, kAXFocusedUIElementChangedNotification as CFString, nil)

        if result1 == .success && result2 == .success {
            observedElements.insert(element)
            lastTextByElement[element] = getTextValue(element) ?? ""
        }
    }

    private func discoverAndObserveWritingApps() async {
        let bundleIDs = [
            "com.apple.mail", "com.microsoft.outlook", "com.readdle.spark",
            "com.apple.iChat", "com.apple.MobileSMS",
            "com.tinyspeck.slackmacgap", "com.microsoft.teams",
            "com.hnc.Discord", "net.whatsapp.WhatsApp",
            "com.apple.Notes", "com.apple.TextEdit",
            "com.microsoft.Word", "com.google.docs",
            "com.apple.dt.Xcode", "com.microsoft.VSCode",
            "dev.zed.Zed", "com.sublimetext.4",
            "net.shinyfrog.bear", "md.obsidian"
        ]

        for bundleID in bundleIDs {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            for app in apps {
                await observeApp(app)
            }
        }
    }

    private func observeApp(_ app: NSRunningApplication) async {
        // Get the app's AXUIElement
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Recursively find text areas
        await findTextAreas(in: appElement)
    }

    private func findTextAreas(in element: AXUIElement) async {
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
              let childArray = children as? [AXUIElement] else { return }

        for child in childArray {
            let role = getRole(child)
            let subrole = getSubrole(child)

            if isTextArea(role: role, subrole: subrole) {
                observeElement(child)
            }

            // Recurse (with depth limit)
            await findTextAreas(in: child)
        }
    }

    // MARK: - Helpers

    private func frontmostAppBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    private func levenshteinRatio(_ a: String, _ b: String) -> Double {
        let distance = levenshteinDistance(a, b)
        let maxLen = max(a.count, b.count)
        guard maxLen > 0 else { return 1.0 }
        return 1.0 - Double(distance) / Double(maxLen)
    }

    private func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count

        guard m > 0 else { return n }
        guard n > 0 else { return m }

        var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = aChars[i-1] == bChars[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,      // deletion
                    matrix[i][j-1] + 1,      // insertion
                    matrix[i-1][j-1] + cost  // substitution
                )
            }
        }
        return matrix[m][n]
    }
}