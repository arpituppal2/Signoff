import Foundation
import SwiftData

@Model
public final class Bucket: @unchecked Sendable {
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
                postfixMode: BucketPostfixMode = .nothing) {
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
        case BucketID.standard.rawValue: return "balanced"
        case BucketID.professional.rawValue: return toneValue.map { $0 > 0.5 ? "casual" : "formal" } ?? "neutral"
        case BucketID.unhinged.rawValue: return unhingedLevel?.rawValue ?? "regular"
        case BucketID.custom.rawValue: return "custom"
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
    case custom
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
    /// Default 6 buckets, all available (app is free and open source).
    static func defaultBuckets() -> [Bucket] {
        return BucketID.allCases.compactMap { bid -> Bucket? in
            guard bid != .generalLegacy else { return nil }
            switch bid {
        case .standard:     return Bucket(id: bid.rawValue, name: "Standard",    iconSymbol: "text.alignleft",                sortOrder: 0, isEnabled: true, emojiEnabled: false)
        case .professional: return Bucket(id: bid.rawValue, name: "Professional",iconSymbol: "person.text.rectangle.fill",    sortOrder: 1, isEnabled: true, toneValue: 0.5, emojiEnabled: false)
        case .unhinged:     return Bucket(id: bid.rawValue, name: "Unhinged",    iconSymbol: "bolt.fill",                    sortOrder: 2, isEnabled: true, unhingedLevel: .regular, emojiEnabled: true)
        case .custom:       return Bucket(id: bid.rawValue, name: "Custom",      iconSymbol: "asterisk.circle.fill",         sortOrder: 3, isEnabled: true, customInstructions: "", emojiEnabled: false)
        case .list:         return Bucket(id: bid.rawValue, name: "My List",     iconSymbol: "list.bullet.rectangle.portrait",sortOrder: 4, isEnabled: true, emojiEnabled: false, phraseListJSON: "")
        case .footer:       return Bucket(id: bid.rawValue, name: "Footer",      iconSymbol: "signature",                    sortOrder: 5, isEnabled: true, emojiEnabled: false, postfixMode: .nothing)
            case .generalLegacy: return nil
            }
        }
    }
}
