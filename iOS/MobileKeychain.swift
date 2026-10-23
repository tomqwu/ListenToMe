import Foundation
import Security

@MainActor
enum MobileKeychain {
    /// The Ollama Cloud key. Each credential has its own account, so no key is ever sent to
    /// another provider's server.
    static let ollamaAccount = "ollama"
    /// The OpenAI-compatible server key (issue #52), bound to one server origin by `MobileOpenAISettings`.
    static let openAIAccount = "openai-compatible"

    private static func query(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: "com.tomwu.ListenToMe.ios", kSecAttrAccount: account]
    }

    static func read(account: String = ollamaAccount) throws -> String {
        var request = query(account)
        request[kSecReturnData] = true
        request[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { throw failure(status) }
        return key
    }

    static func save(_ key: String, account: String = ollamaAccount) throws {
        let item = query(account)
        if key.isEmpty {
            let status = SecItemDelete(item as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
            return
        }
        let values: [CFString: Any] = [kSecValueData: Data(key.utf8),
                                     kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(item as CFDictionary, values as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw failure(status) }
        let added = SecItemAdd(item.merging(values) { _, new in new } as CFDictionary, nil)
        guard added == errSecSuccess else { throw failure(added) }
    }

    private static func failure(_ status: OSStatus) -> RecordingError {
        .message("Could not access the API key in Keychain (\(status)). Unlock your device and try again.")
    }
}
