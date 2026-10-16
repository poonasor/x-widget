import Foundation
import Security

struct XToken: Codable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var userID: String?

    var isExpiring: Bool { expiresAt.timeIntervalSinceNow < 120 }
}

/// Stores the OAuth token in a keychain access group shared with the widget.
enum TokenStore {
    private static let service = "ca.perpetualmedia.XWidget.oauth"
    private static let account = "x"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: AppGroup.keychainGroup,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    static func load() -> XToken? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(XToken.self, from: data)
    }

    static func save(_ token: XToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
