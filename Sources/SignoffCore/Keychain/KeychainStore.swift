import Foundation
import Security

/// Thread-safe Keychain wrapper for special-purpose accounts (quota, fingerprint,
/// stripe receipt). Service identifier `com.signoff`. Items use
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` so they cannot escape the device
/// even through iCloud Keychain sync.
public final class KeychainStore: @unchecked Sendable {
    public static let shared = KeychainStore(service: "com.signoff", accessGroup: nil)
    private let service: String
    private let accessGroup: String?

    public init(service: String, accessGroup: String?) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public func loadString(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let s = String(data: data, encoding: .utf8) else { return nil }
            return s
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.osStatus(status, account: account)
        }
    }

    public func upsertString(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        var query = baseQuery(account: account)
        query[kSecValueData as String] = data

        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var insert = baseQuery(account: account)
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw KeychainError.osStatus(addStatus, account: account)
            }
        } else if status != errSecSuccess {
            throw KeychainError.osStatus(status, account: account)
        }
    }

    public func delete(account: String) throws {
        let query = baseQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.osStatus(status, account: account)
        }
    }

    public func loadJSON<T: Decodable>(_ type: T.Type, account: String) throws -> T? {
        guard let raw = try loadString(account: account) else { return nil }
        let data = Data(raw.utf8)
        return try JSONDecoder.signed.decode(type, from: data)
    }

    public func saveJSON<T: Encodable>(_ value: T, account: String) throws {
        let data = try JSONEncoder.signed.encode(value)
        let str = String(decoding: data, as: UTF8.self)
        try upsertString(str, account: account)
    }

    private func baseQuery(account: String) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let g = accessGroup { q[kSecAttrAccessGroup as String] = g }
        return q
    }
}

public enum KeychainError: Error, CustomStringConvertible {
    case osStatus(OSStatus, account: String)
    public var description: String {
        switch self {
        case .osStatus(let s, let a):
            let raw = SecCopyErrorMessageString(s, nil) as String? ?? "OSStatus \(s)"
            return "Keychain[com.signoff/\(a)] failed: \(raw)"
        }
    }
}

public extension JSONEncoder {
    static let signed: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()
}

public extension JSONDecoder {
    static let signed: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
