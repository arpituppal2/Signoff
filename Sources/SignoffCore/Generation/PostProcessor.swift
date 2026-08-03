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
            let included = profile.includedFooterFields
            var lines: [String] = [cleaned, ""]
            if included.contains(FooterField.name.rawValue), !profile.name.isEmpty { lines.append(profile.name) }
            if included.contains(FooterField.title.rawValue), let t = profile.title, !t.isEmpty { lines.append(t) }
            if included.contains(FooterField.company.rawValue), let c = profile.company, !c.isEmpty { lines.append(c) }
            if included.contains(FooterField.email.rawValue), let e = profile.email, !e.isEmpty  { lines.append(e) }
            if included.contains(FooterField.phone.rawValue), let p = profile.phone, !p.isEmpty  { lines.append(p) }
            if included.contains(FooterField.website.rawValue), let w = profile.website, !w.isEmpty { lines.append(w) }
            return lines.joined(separator: "\n")
        }
    }
}

/// Identity fields that can appear in a signoff's full footer. The user picks
/// which of these to include; `UserProfileSnapshot` carries that selection into
/// the (Sendable) generation pipeline.
public enum FooterField: String, CaseIterable, Sendable {
    case name, title, company, email, phone, website

    public var displayName: String {
        rawValue.capitalized
    }

    /// Persisted raw-value form. `nil` means "all fields" (default).
    public static func encode(_ fields: Set<String>) -> String? {
        let all = Set(allCases.map(\.rawValue))
        guard fields != all else { return nil }
        return fields.sorted().joined(separator: ",")
    }

    public static func decode(_ raw: String?) -> Set<String> {
        guard let raw, !raw.isEmpty else { return Set(allCases.map(\.rawValue)) }
        return Set(raw.split(separator: ",").map(String.init))
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
    public let includedFooterFields: Set<String>

    public init(profile: UserProfile? = nil) {
        self.name = profile?.name ?? ""
        self.title = profile?.title
        self.company = profile?.company
        self.email = profile?.email
        self.phone = profile?.phone
        self.website = profile?.website
        self.selfDescription = profile?.selfDescription ?? ""
        self.emojiEnabled = profile?.emojiEnabled ?? false
        self.includedFooterFields = FooterField.decode(profile?.footerFieldsRaw)
    }
}
