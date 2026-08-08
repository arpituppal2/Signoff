import Foundation
import SwiftData

@Model
public final class Bucket {
    @Attribute(.unique) public var id: String
    public var name: String
    public var iconSymbol: String          // SF Symbol name
    public var accentHex: String           // currently always amber
    public var sortOrder: Int
    public var isEnabled: Bool
    public var isCustom: Bool

    // Tone & level (per-bucket config)
    public var toneValue: Double?          // 0…1 (Professional)
    public var unhingedLevelRaw: String?   // calm|regular|deranged|cynical
    public var cynicalOptIn: Bool
    public var emojiEnabled: Bool          // per-bucket emoji toggle (spec §5)
    public var customInstructions: String?
    public var phraseListJSON: String?
    public var postfixModeRaw: String      // nothing|name|fullFooter

    // v3.5: Cynical bucket — permit explicit/raunchy output (default off).
    public var nsfwEnabled: Bool
    // v3.5: Custom bucket — user-authored rich text footer (RTFD data; may
    // embed an image via NSTextAttachment). `nil`/empty = not configured yet.
    public var footerRTFData: Data?

    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String,
                name: String,
                iconSymbol: String,
                sortOrder: Int,
                isEnabled: Bool = true,
                isCustom: Bool = false,
                toneValue: Double? = nil,
                unhingedLevel: UnhingedLevel? = nil,
                customInstructions: String? = nil,
                cynicalOptIn: Bool = false,
                emojiEnabled: Bool = false,
                phraseListJSON: String? = nil,
                postfixMode: BucketPostfixMode = .nothing,
                nsfwEnabled: Bool = false,
                footerRTFData: Data? = nil) {
        self.id = id
        self.name = name
        self.iconSymbol = iconSymbol
        self.accentHex = "#D4A017"
        self.sortOrder = sortOrder
        self.isEnabled = isEnabled
        self.isCustom = isCustom
        self.toneValue = toneValue
        self.unhingedLevelRaw = unhingedLevel?.rawValue
        self.cynicalOptIn = cynicalOptIn
        self.emojiEnabled = emojiEnabled
        self.customInstructions = customInstructions
        self.phraseListJSON = phraseListJSON
        self.postfixModeRaw = postfixMode.rawValue
        self.nsfwEnabled = nsfwEnabled
        self.footerRTFData = footerRTFData
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }

    public var unhingedLevel: UnhingedLevel? {
        get { unhingedLevelRaw.flatMap(UnhingedLevel.init(rawValue:)) }
        set { unhingedLevelRaw = newValue?.rawValue }
    }

    public var postfixMode: BucketPostfixMode {
        get { BucketPostfixMode(rawValue: postfixModeRaw) ?? .nothing }
        set {
            postfixModeRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    public var toneLabel: String {
        switch id {
        case BucketID.standard.rawValue: return "normal"
        case BucketID.professional.rawValue: return toneValue.map { $0 > 0.5 ? "casual" : "formal" } ?? "neutral"
        case BucketID.unhinged.rawValue: return unhingedLevel?.rawValue ?? "regular"
        case BucketID.list.rawValue: return "phrase"
        case BucketID.footer.rawValue: return postfixMode.rawValue
        default: return "default"
        }
    }
}

public enum BucketID: String, CaseIterable, Sendable {
    case standard
    case professional
    case unhinged
    case list
    case footer
    /// legacy v1 ID — must be migrated to `standard` on first v2 launch (§14.2.1)
    case generalLegacy = "general"
}

public enum UnhingedLevel: String, CaseIterable, Sendable {
    case calm, regular, deranged, cynical
}

public enum BucketPostfixMode: String, CaseIterable, Sendable {
    case nothing, name, fullFooter
}

public extension Bucket {
    /// Default 3 buckets: Normal / Professional / Cynical.
    /// Shortcut digits: 1 Normal, 2 Professional, 3 Cynical
    /// (` is the menu-bar opener). `standard` and `unhinged` keep their
    /// internal IDs (store + history stability) but display as "Normal" and
    /// "Cynical". "My List" and "Footer" were removed in the v3 slim.
    static func defaultBuckets() -> [Bucket] {
        return BucketID.allCases.compactMap { bid -> Bucket? in
            guard bid != .generalLegacy else { return nil }
            switch bid {
        case .standard:     return Bucket(id: bid.rawValue, name: "Normal",     iconSymbol: "text.alignleft",                sortOrder: 0, isEnabled: true, emojiEnabled: false)
        case .professional: return Bucket(id: bid.rawValue, name: "Professional",iconSymbol: "person.text.rectangle.fill",    sortOrder: 1, isEnabled: true, toneValue: 0.5, emojiEnabled: false)
        case .unhinged:     return Bucket(id: bid.rawValue, name: "Cynical",     iconSymbol: "bolt.fill",                    sortOrder: 2, isEnabled: true, unhingedLevel: .cynical, emojiEnabled: true)
            case .list:         return nil
            case .footer:       return nil
            case .generalLegacy: return nil
            }
        }
    }
}
