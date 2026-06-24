import Foundation
import Security

/// Thin wrapper around the macOS generic-password Keychain.
/// Uses the file-based login keychain (no `kSecAttrAccessible` key).
enum KeychainStore {
    private static let service = "com.tomwu.ListenToMe"

    /// Returns the stored string for `account`, or nil if not found.
    static func get(_ account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    /// Stores `value` for `account`. Passing nil or an empty string deletes the entry.
    /// Returns true on success.
    @discardableResult
    static func set(_ value: String?, for account: String) -> Bool {
        guard let value, !value.isEmpty else {
            return delete(account)
        }
        guard let data = value.data(using: .utf8) else { return false }

        // Try to update an existing item first.
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let update: [CFString: Any] = [kSecValueData: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        // Item did not exist — add it.
        var addQuery = query
        addQuery[kSecValueData] = data
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    /// Deletes the entry for `account`. Returns true if deleted or not found.
    @discardableResult
    static func delete(_ account: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
