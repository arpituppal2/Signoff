import Foundation

/// Minimal post-processor for FM-generated signoffs.
/// Spec §3: FM handles quality — no stop word filtering, no Jaccard dedup,
/// no emoji injection. Only add sentence-ending punctuation and handle footers.
public struct PostProcessor: Sendable {

    public init() {}

    /// Ensure the signoff ends with sentence-ending punctuation.
    public static func ensurePunctuation(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, !t.hasSuffix("."), !t.hasSuffix("!"), !t.hasSuffix("?") {
            t += "."
        }
        return t
    }

    /// Append profile footer based on mode.
    public static func appendFooter(_ text: String, profile: UserProfileSnapshot, mode: BucketPostfixMode) -> String {
        let cleaned = ensurePunctuation(text)
        switch mode {
        case .nothing:
            return cleaned
        case .name:
            return "\(cleaned)\n\n—\(profile.name)"
        case .fullFooter:
            var lines: [String] = [cleaned, ""]
            if !profile.name.isEmpty   { lines.append(profile.name) }
            if let t = profile.title, !t.isEmpty { lines.append(t) }
            if let c = profile.company, !c.isEmpty { lines.append(c) }
            if let e = profile.email, !e.isEmpty  { lines.append(e) }
            if let p = profile.phone, !p.isEmpty  { lines.append(p) }
            if let w = profile.website, !w.isEmpty { lines.append(w) }
            return lines.joined(separator: "\n")
        }
    }
}

public struct UserProfileSnapshot: Sendable, Equatable {
    public let name: String
    public let title: String?
    public let company: String?
    public let email: String?
    public let phone: String?
    public let website: String?
    public let selfDescription: String
    public let emojiEnabled: Bool

    public init(profile: UserProfile? = nil) {
        self.name = profile?.name ?? ""
        self.title = profile?.title
        self.company = profile?.company
        self.email = profile?.email
        self.phone = profile?.phone
        self.website = profile?.website
        self.selfDescription = profile?.selfDescription ?? ""
        self.emojiEnabled = profile?.emojiEnabled ?? false
    }
}
