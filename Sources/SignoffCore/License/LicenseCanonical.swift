import Foundation

/// Canonical JSON encoder used to compute the verify payload. MUST be byte-identical
/// to the encoder used by the offline `tools/license-issuer/` CLI when signing, or
/// signatures on legitimate licenses will not validate against the public key.
/// - sortedKeys: deterministic key order
/// - ISO8601 (`.withInternetDateTime`): stable date format
/// - withoutEscapingSlashes: fewer URL escapes that the issuer also skips
public enum ClaimsEncoder {
    public static let shared: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()
}

public enum ClaimsDecoder {
    public static let shared: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
