import Foundation
import CryptoKit
import CommonCrypto

/// An ephemeral local QR import, never Codable or part of AppData/backups.
/// Parsing does not save a credential, enable consent or make network requests.
struct CoachOnlineSetupLink: Identifiable {
    let id = UUID()
    let endpoint: String
    private let payload: Data
    let issuedAt: Date

    func isCurrent(at now: Date) -> Bool {
        let age = now.timeIntervalSince(issuedAt)
        return age.isFinite && age >= -60 && age <= 300
    }

    /// The code unlocks the local capsule only. Consent is never enabled here.
    func configuration(code: String, now: Date) -> CoachOnlineConfiguration? {
        guard isCurrent(at: now), code.count <= 32 else { return nil }
        let clean = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().replacingOccurrences(of: "-", with: "")
        let alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        guard clean.count == 10, clean.allSatisfy({ alphabet.contains($0) }) else { return nil }
        let salt = Data(payload.prefix(16))
        var keyBytes = [UInt8](repeating: 0, count: 32)
        defer { for index in keyBytes.indices { keyBytes[index] = 0 } }
        let status = keyBytes.withUnsafeMutableBufferPointer { output in
            clean.withCString { password in
                salt.withUnsafeBytes { source in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password, clean.utf8.count,
                        source.bindMemory(to: UInt8.self).baseAddress!, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 100_000,
                        output.baseAddress!, output.count)
                }
            }
        }
        guard status == 0,
              let box = try? AES.GCM.SealedBox(combined: Data(payload.dropFirst(16))) else { return nil }
        let key = SymmetricKey(data: Data(keyBytes))
        let context = Data("PivotCoachSetupV2|\(endpoint)|\(Int(issuedAt.timeIntervalSince1970))".utf8)
        guard let clear = try? AES.GCM.open(box, using: key, authenticating: context),
              let token = String(data: clear, encoding: .utf8),
              CoachOnlineConfiguration(endpoint: endpoint, token: token, consent: true).valid else { return nil }
        return .init(endpoint: endpoint, token: token, consent: false)
    }

    static func parse(_ url: URL, now: Date) -> Self? {
        guard url.absoluteString.utf8.count <= 2048,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "pivot", parts.host == "coach-setup", parts.path.isEmpty,
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
              let items = parts.queryItems, items.count == 4,
              Set(items.map(\.name)) == Set(["version", "issued", "endpoint", "payload"]),
              items.allSatisfy({ $0.value != nil }) else { return nil }
        let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
        guard fields["version"] == "2", let stamp = fields["issued"],
              (1...15).contains(stamp.count), stamp.allSatisfy({ $0.isASCII && $0.isNumber }),
              let seconds = Double(stamp), seconds.isFinite,
              let endpoint = fields["endpoint"],
              CoachOnlineConfiguration(endpoint: endpoint, token: String(repeating: "a", count: 43), consent: true).url != nil,
              let encoded = fields["payload"], (116...230).contains(encoded.count),
              encoded.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        let base64 = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padding = String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let bytes = Data(base64Encoded: base64 + padding), (87...172).contains(bytes.count) else { return nil }
        let value = Self(endpoint: endpoint, payload: bytes, issuedAt: Date(timeIntervalSince1970: seconds))
        return value.isCurrent(at: now) ? value : nil
    }
}
