import Foundation
import CryptoKit
import CommonCrypto

enum EncryptedBackupError: LocalizedError {
    case passwordRequired, invalidPassword, mismatchedPasswords, invalidArchive, authenticationFailed, tooLarge, unavailable
    var errorDescription: String? {
        switch self {
        case .passwordRequired: return "Inserisci la password del backup cifrato."
        case .invalidPassword: return "Scegli una password da 12 a 256 caratteri, non composta soltanto da spazi."
        case .mismatchedPasswords: return "Le due password non coincidono."
        case .invalidArchive: return "Il formato del backup cifrato non è valido o non è supportato."
        case .authenticationFailed: return "Password errata o backup danneggiato. Nessun dato è stato sostituito."
        case .tooLarge: return "Il backup supera il limite di sicurezza di 80 MB. Nessun dato è stato sostituito."
        case .unavailable: return "La protezione del backup non è disponibile. Nessuna copia in chiaro verrà creata."
        }
    }
}

/// Stored ONLY in this device's non-synchronizing Keychain, never in AppData.
/// Automatic copies need the derived encryption key, not the password itself.
struct BackupEncryptionKey: Codable {
    let salt: Data
    let key: Data
    var valid: Bool { salt.count == 16 && key.count == 32 }
    // Public random salt; a new password configuration gets a separate file so
    // prior archives are not overwritten or re-encrypted without their password.
    var identifier: String { salt.map { String(format: "%02x", $0) }.joined() }
}

enum EncryptedBackup {
    static let maximumBytes = 80 * 1024 * 1024
    private static let magic = Data("PivotEncryptedBackup1\n".utf8)
    private static let family = Data("PivotEncryptedBackup".utf8)
    private static let iterations: UInt32 = 600_000

    static func normalized(_ password: String) -> String { password.precomposedStringWithCanonicalMapping }

    static func prepare(password: String, confirmation: String) throws -> BackupEncryptionKey {
        guard normalized(password) == normalized(confirmation) else { throw EncryptedBackupError.mismatchedPasswords }
        let salt = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        return try derive(password: password, salt: salt)
    }

    private static func derive(password: String, salt: Data) throws -> BackupEncryptionKey {
        let clean = normalized(password)
        guard (12...256).contains(clean.count), clean.utf8.count <= 1024, !clean.utf8.contains(0),
              !clean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, salt.count == 16 else {
            throw EncryptedBackupError.invalidPassword
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        defer { for i in bytes.indices { bytes[i] = 0 } }
        let status = bytes.withUnsafeMutableBufferPointer { output in
            clean.withCString { pass in
                salt.withUnsafeBytes { source in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pass, clean.utf8.count,
                        source.bindMemory(to: UInt8.self).baseAddress!, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations, output.baseAddress!, output.count)
                }
            }
        }
        guard status == kCCSuccess else { throw EncryptedBackupError.unavailable }
        return .init(salt: salt, key: Data(bytes))
    }

    static func seal(_ clear: Data, using protection: BackupEncryptionKey) throws -> Data {
        guard protection.valid else { throw EncryptedBackupError.unavailable }
        guard clear.count <= maximumBytes - magic.count - 16 - 28 else { throw EncryptedBackupError.tooLarge }
        let header = magic + protection.salt
        let box = try AES.GCM.seal(clear, using: SymmetricKey(data: protection.key), authenticating: header)
        guard let combined = box.combined else { throw EncryptedBackupError.unavailable }
        return header + combined
    }

    static func open(_ archive: Data, password: String?) throws -> Data {
        guard let password, !password.isEmpty else { throw EncryptedBackupError.passwordRequired }
        let salt = try checkedSalt(archive)
        let protection = try derive(password: password, salt: salt)
        return try open(archive, using: protection)
    }

    static func open(_ archive: Data, using protection: BackupEncryptionKey) throws -> Data {
        let salt = try checkedSalt(archive)
        guard protection.valid, protection.salt == salt else { throw EncryptedBackupError.authenticationFailed }
        let headerSize = magic.count + 16
        do {
            let box = try AES.GCM.SealedBox(combined: Data(archive.dropFirst(headerSize)))
            return try AES.GCM.open(box, using: SymmetricKey(data: protection.key), authenticating: Data(archive.prefix(headerSize)))
        } catch { throw EncryptedBackupError.authenticationFailed }
    }

    private static func checkedSalt(_ archive: Data) throws -> Data {
        guard archive.count <= maximumBytes else { throw EncryptedBackupError.tooLarge }
        guard archive.starts(with: magic), archive.count >= magic.count + 16 + 28 else { throw EncryptedBackupError.invalidArchive }
        return Data(archive.dropFirst(magic.count).prefix(16))
    }

    /// Legacy JSON remains readable, never silently rewritten during import.
    static func decoded(_ archive: Data, password: String? = nil) throws -> AppData {
        guard archive.count <= maximumBytes else { throw EncryptedBackupError.tooLarge }
        if archive.starts(with: family) { return try BackupCodec.decode(open(archive, password: password)) }
        return try BackupCodec.decode(archive)
    }

    static func read(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var bytes = Data()
        while true {
            let remaining = maximumBytes + 1 - bytes.count
            let chunk = try handle.read(upToCount: min(1024 * 1024, remaining)) ?? Data()
            if chunk.isEmpty { return bytes }
            bytes.append(chunk)
            guard bytes.count <= maximumBytes else { throw EncryptedBackupError.tooLarge }
        }
    }
}
