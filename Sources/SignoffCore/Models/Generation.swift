import Foundation
import SwiftData

@Model
public final class SignoffGeneration {
    @Attribute(.unique) public var id: String
    public var bucketId: String
    public var text: String
    public var tone: String?
    public var isFavorite: Bool
    public var wasCopied: Bool
    public var wasInserted: Bool
    public var createdAt: Date
    public var latencyMs: Int
    public var providerRaw: String
    public var modelVersion: String?

    public init(id: String = UUID().uuidString,
                bucketId: String,
                text: String,
                tone: String? = nil,
                isFavorite: Bool = false,
                wasCopied: Bool = false,
                wasInserted: Bool = false,
                createdAt: Date = Date(),
                latencyMs: Int = 0,
                providerRaw: String = GenerationProviderKind.foundationModels.rawValue,
                modelVersion: String? = nil) {
        self.id = id
        self.bucketId = bucketId
        self.text = text
        self.tone = tone
        self.isFavorite = isFavorite
        self.wasCopied = wasCopied
        self.wasInserted = wasInserted
        self.createdAt = createdAt
        self.latencyMs = latencyMs
        self.providerRaw = providerRaw
        self.modelVersion = modelVersion
    }
}

public extension SignoffGeneration {
    @MainActor static func preview(text: String, bucket: String = "standard") -> SignoffGeneration {
        SignoffGeneration(bucketId: bucket, text: text)
    }
}
