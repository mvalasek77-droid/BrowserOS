import Foundation
import Security

/// Stores login credentials per-host in the iPhone's Keychain. The watch never
/// sees the values; it only asks to save or fill them for the current page.
enum LoginStore {
    private static let service = "com.steroidos.ios.logins"

    /// Returns true when this save actually changed something.
    @discardableResult
    static func save(host: String, username: String, password: String) -> Bool {
        guard !host.isEmpty, !password.isEmpty else { return false }
        let data = Data("\(username)\u{1F}\(password)".utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    static func load(host: String) -> SavedLogin? {
        guard !host.isEmpty else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let raw = String(data: data, encoding: .utf8) else { return nil }
        let parts = raw.components(separatedBy: "\u{1F}")
        guard parts.count == 2 else { return nil }
        return SavedLogin(host: host, username: parts[0], password: parts[1])
    }

    @discardableResult
    static func delete(host: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}