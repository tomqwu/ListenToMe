import Foundation
import Security

@MainActor
enum MobileKeychain {
    private static let query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "com.tomwu.ListenToMe.ios",
        kSecAttrAccount: "ollama"
    ]

    static func read() throws -> String {
        var request = query
        request[kSecReturnData] = true
        request[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { throw failure(status) }
        return key
    }

    static func save(_ key: String) throws {
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
            return
        }
        let values: [CFString: Any] = [kSecValueData: Data(key.utf8),
                                     kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw failure(status) }
        let added = SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil)
        guard added == errSecSuccess else { throw failure(added) }
    }

    private static func failure(_ status: OSStatus) -> RecordingError {
        .message("Could not access the API key in Keychain (\(status)). Unlock your device and try again.")
    }
}
