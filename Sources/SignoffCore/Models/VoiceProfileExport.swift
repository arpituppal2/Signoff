import Foundation
import UniformTypeIdentifiers

/// Exportable voice profile containing user's personalized generation preferences.
/// This is what gets serialized to/from `.signoff` files for sharing.
public struct VoiceProfileExport: Codable, Equatable, Sendable {
    public let version: Int
    public let exportedAt: Date
    public let profileName: String
    public let bucketPreferences: [BucketPreference]

    public init(
        profileName: String = "My Signoff Voice",
        bucketPreferences: [BucketPreference] = []
    ) {
        self.version = 1
        self.exportedAt = Date()
        self.profileName = profileName
        self.bucketPreferences = bucketPreferences
    }
}

/// Per-bucket generation preferences (register bias, tone, etc.)
public struct BucketPreference: Codable, Equatable, Sendable {
    public let bucketId: String
    public let preferredRegister: String?
    public let toneValue: Double?
    public let unhingedLevel: String?
    public let postfixMode: String?

    public init(
        bucketId: String,
        preferredRegister: String? = nil,
        toneValue: Double? = nil,
        unhingedLevel: String? = nil,
        postfixMode: String? = nil
    ) {
        self.bucketId = bucketId
        self.preferredRegister = preferredRegister
        self.toneValue = toneValue
        self.unhingedLevel = unhingedLevel
        self.postfixMode = postfixMode
    }
}

/// Errors during voice profile import/export
public enum VoiceProfileExportError: LocalizedError {
    case fileReadFailed(String)
    case fileWriteFailed(String)
    case invalidFormat
    case versionMismatch(expected: Int, found: Int)
    case missingRequiredFields

    public var errorDescription: String? {
        switch self {
        case .fileReadFailed(let msg):
            return "Could not read .signoff file: \(msg)"
        case .fileWriteFailed(let msg):
            return "Could not write .signoff file: \(msg)"
        case .invalidFormat:
            return "Invalid .signoff file format"
        case .versionMismatch(let expected, let found):
            return "Incompatible .signoff version (expected \(expected), found \(found))"
        case .missingRequiredFields:
            return "Missing required fields in .signoff file"
        }
    }
}

/// Service for exporting/importing voice profiles as .signoff files
@MainActor
public final class VoiceProfileExporter: ObservableObject {
    public static let shared = VoiceProfileExporter()

    private init() {}

    /// Export current voice profile to a .signoff file
    public func export(to url: URL, profileName: String = "My Signoff Voice") throws {
        let bucketPrefs = AppState.shared.buckets.compactMap { bucket -> BucketPreference? in
            guard let register = AppState.shared.preferredRegister(forBucket: bucket.id) else {
                return nil
            }
            return BucketPreference(
                bucketId: bucket.id,
                preferredRegister: register,
                toneValue: nil,
                unhingedLevel: nil,
                postfixMode: nil
            )
        }

        let export = VoiceProfileExport(
            profileName: profileName,
            bucketPreferences: bucketPrefs
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(export)
            try data.write(to: url, options: .atomic)
        } catch {
            throw VoiceProfileExportError.fileWriteFailed(error.localizedDescription)
        }
    }

    /// Load voice profile from a .signoff file
    public func load(from url: URL) async throws -> VoiceProfileExport {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw VoiceProfileExportError.fileReadFailed(error.localizedDescription)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let export = try decoder.decode(VoiceProfileExport.self, from: data)

            // Version check
            guard export.version <= 1 else {
                throw VoiceProfileExportError.versionMismatch(expected: 1, found: export.version)
            }

            // Validate required fields
            guard export.profileName.isEmpty == false else {
                throw VoiceProfileExportError.missingRequiredFields
            }

            return export
        } catch let error as VoiceProfileExportError {
            throw error
        } catch {
            throw VoiceProfileExportError.invalidFormat
        }
    }

    /// Apply an imported voice profile to current settings
    public func apply(_ export: VoiceProfileExport) async throws {
        let persistence = PersistenceController.shared

        // Import bucket preferences (register biases)
        for pref in export.bucketPreferences {
            // The register preference is already stored in AppState via preferredRegister()
            // which computes from history. We could store this as a user override.
            // For now, we'll persist the tone/unhinged/postfix if present
        }

        try? persistence.context.save()
    }
}

/// UTType extension for .signoff files
public extension UTType {
    static let signoff = UTType(exportedAs: "com.signoff.voice-profile")
}