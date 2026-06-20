import Foundation
import Security

/// Minimal generic-password Keychain wrapper for storing small secrets (e.g. API keys)
/// in the login keychain, keyed by a string account under a fixed service.
enum KeychainStore {
    private static let service = "com.tomwu.ListenToMe"

    /// Stores (or replaces) the value for `account`. Pass `nil`/empty to delete.
    @discardableResult
    static func set(_ value: String?, for account: String) -> Bool {
        // Delete any existing item first (simplest correct upsert).
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let deleteStatus = SecItemDelete(base as CFDictionary)

        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else {
            // Delete-only: success only if it was removed or wasn't present.
            return deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound
        }
        var add = base
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    /// Returns the stored value for `account`, or nil if absent.
    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    /// Removes the stored value for `account`.
    @discardableResult
    static func delete(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
