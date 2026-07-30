import Foundation
import SwiftData

@Model
public final class UserProfile: @unchecked Sendable {
    public var name: String
    public var title: String?
    public var company: String?
    public var email: String?
    public var phone: String?
    public var website: String?
    public var linkedin: String?
    public var selfDescription: String
    public var emojiEnabled: Bool
    public var updatedAt: Date

    public init(name: String,
                title: String? = nil,
                company: String? = nil,
                email: String? = nil,
                phone: String? = nil,
                website: String? = nil,
                linkedin: String? = nil,
                selfDescription: String = "",
                emojiEnabled: Bool = false,
                updatedAt: Date = Date()) {
        self.name = name
        self.title = title
        self.company = company
        self.email = email
        self.phone = phone
        self.website = website
        self.linkedin = linkedin
        self.selfDescription = selfDescription
        self.emojiEnabled = emojiEnabled
        self.updatedAt = updatedAt
    }
}

public extension UserProfile {
    static func makeEmpty() -> UserProfile { UserProfile(name: "") }
    static func makeSample() -> UserProfile {
        UserProfile(name: "Alex",
                    title: "Engineer",
                    company: "Signoff",
                    email: "alex@signoff.app",
                    selfDescription: "writes terse, occasionally kind emails")
    }
}
