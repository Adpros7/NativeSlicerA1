import Foundation
import Security

/// Minimal macOS Keychain wrapper for third-party API credentials (API
/// keys, OAuth client secrets/tokens). AGENTS.md §10: "Never hardcode
/// credentials... Use macOS Keychain." No UserDefaults/plaintext-file
/// fallback — if the Keychain call fails, callers see `nil`/the thrown
/// error rather than a silently-degraded storage path.
///
/// Generic-password items, keyed by `service` (a reverse-DNS-style string
/// identifying which integration owns the secret) + `account` (which
/// credential within that integration, e.g. "apiKey"/"accessToken").
/// `AfterFirstUnlockThisDeviceOnly` (P8-002 security review): readable
/// as soon as the user unlocks their Mac once after boot (so background/
/// launch-time reads work), but explicitly excluded from iCloud
/// Keychain sync — these are third-party API tokens for THIS app on
/// THIS Mac, not something that should silently propagate to every
/// other Mac signed into the same iCloud account.
enum KeychainStore {
    @discardableResult
    static func set(_ value: String, service: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func get(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    @discardableResult
    static func delete(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
