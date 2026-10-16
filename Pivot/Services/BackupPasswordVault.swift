import Foundation
import Security

/// No credential leaves Keychain or enters exported AppData, logs or defaults.
enum BackupPasswordVault {
    private static var service: String {
        let base = "app.pivot.personal.backup-encryption.v1"
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--interaction-test"),
           let value = ProcessInfo.processInfo.environment["PIVOT_QA_KEYCHAIN_ID"], let id = UUID(uuidString: value) {
            return base + ".qa." + id.uuidString
        }
        #endif
        return base
    }
    private static func query(_ installationID: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: installationID.uuidString, kSecAttrSynchronizable as String: false]
    }
    static func configured(for installationID: UUID) -> Bool {
        var attributes = query(installationID)
        attributes[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(attributes as CFDictionary, nil) == errSecSuccess
    }
    static func load(for installationID: UUID) throws -> BackupEncryptionKey {
        var attributes = query(installationID)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &item) == errSecSuccess,
              let bytes = item as? Data, let key = try? JSONDecoder().decode(BackupEncryptionKey.self, from: bytes), key.valid else {
            throw EncryptedBackupError.unavailable
        }
        return key
    }
    static func save(_ key: BackupEncryptionKey, for installationID: UUID) throws {
        guard key.valid else { throw EncryptedBackupError.unavailable }
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(key),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query(installationID) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query(installationID).merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess else {
                throw EncryptedBackupError.unavailable
            }
        } else if status != errSecSuccess { throw EncryptedBackupError.unavailable }
    }
}
