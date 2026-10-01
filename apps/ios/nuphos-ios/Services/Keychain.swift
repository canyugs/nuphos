import Foundation
import Security

/// Minimal generic-password wrapper. The session token is the only secret
/// this app holds, and it must survive relaunches without ever touching
/// UserDefaults.
enum Keychain {
    private static let service = "ai.nuphos.ios"

    enum Failure: Error { case unhandled(OSStatus) }

    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    static func read(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let update = SecItemUpdate(baseQuery(key) as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw Failure.unhandled(update) }

        let add = SecItemAdd(baseQuery(key).merging(attributes) { $1 } as CFDictionary, nil)
        guard add == errSecSuccess else { throw Failure.unhandled(add) }
    }

    static func delete(_ key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }
}
