import Foundation
import Security

/// Tokens the user created with `claude setup-token` and entered in Settings,
/// one per Claude profile. Claude Code's own Keychain items are never touched.
enum ClaudeSetupTokenKeychain {
    static let service = "build.gnibu.tokens-on-track.claude-setup-token"

    /// The terminal wraps the long token, so a paste can carry line breaks.
    static func normalized(_ token: String) -> String {
        token.filter { !$0.isWhitespace }
    }

    static func read(account: String) -> String? {
        var query = identity(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else { return nil }
        return token
    }

    @discardableResult
    static func save(_ token: String, account: String) -> Bool {
        let clean = normalized(token)
        guard !clean.isEmpty, let data = clean.data(using: .utf8) else { return false }

        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(identity(account) as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }

        var item = identity(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func remove(account: String) -> Bool {
        let status = SecItemDelete(identity(account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func identity(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
