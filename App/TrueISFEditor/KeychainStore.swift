import Foundation
import Security

enum KeychainStore {
    private static let service = "com.arsonrivvers.TrueISFEditor"
    private static let account = "shadertoy-api-key"

    /// Returns the OSStatus so callers can surface a failed save — `assertionFailure` alone is a
    /// no-op in release, silently dropping the user's key.
    @discardableResult
    static func save(_ key: String) -> OSStatus {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        // Scope the key to this device and only while unlocked (declare intent rather than inherit
        // the default).
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess {
            assertionFailure("KeychainStore.save failed: OSStatus \(status)")
        }
        return status
    }

    /// User-visible message for a failed save; nil on success.
    static func saveErrorMessage(for status: OSStatus) -> String? {
        guard status != errSecSuccess else { return nil }
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return "Couldn't save the key to the Keychain: \(detail)"
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
