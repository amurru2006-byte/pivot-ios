import Foundation

enum SignatureRenewal {
    static let profileByteLimit = 1_048_576
    static let warningInterval: TimeInterval = 72 * 60 * 60
    private static let estimatedValidity: TimeInterval = 7 * 24 * 60 * 60

    struct Confirmation: Codable {
        let profileExpiry: Date
        let confirmedAt: Date
    }

    struct Deadline: Equatable {
        let date: Date
        let estimated: Bool

        func needsReminder(at now: Date) -> Bool {
            date.timeIntervalSince(now) <= SignatureRenewal.warningInterval
        }
    }

    static func deadline(profileExpiry: Date, confirmation: Confirmation?, now: Date) -> Deadline {
        if let confirmation, confirmation.profileExpiry == profileExpiry, confirmation.confirmedAt <= now {
            let estimate = confirmation.confirmedAt.addingTimeInterval(estimatedValidity)
            if estimate > profileExpiry {
                return Deadline(date: estimate, estimated: true)
            }
        }
        return Deadline(date: profileExpiry, estimated: false)
    }

    static func profileExpiry(in profile: Data, bundleID: String) -> Date? {
        guard !profile.isEmpty, profile.count <= profileByteLimit, !bundleID.isEmpty else { return nil }
        let bytes = Array(profile)
        var envelope = DERReader(bytes)
        guard var content = envelope.read(0x30), envelope.isAtEnd,
              content.readOID(endingWith: 0x02),
              var signedWrapper = content.read(0xa0), content.isAtEnd,
              var signed = signedWrapper.read(0x30), signedWrapper.isAtEnd,
              signed.read(0x02) != nil, signed.read(0x31) != nil,
              var encapsulated = signed.read(0x30),
              encapsulated.readOID(endingWith: 0x01),
              var payloadWrapper = encapsulated.read(0xa0), encapsulated.isAtEnd,
              let payload = payloadWrapper.read(0x04), payloadWrapper.isAtEnd,
              let plist = try? PropertyListSerialization.propertyList(from: payload.data, options: [], format: nil),
              let fields = plist as? [String: Any],
              let devices = fields["ProvisionedDevices"] as? [String], !devices.isEmpty,
              let entitlements = fields["Entitlements"] as? [String: Any],
              let identifier = entitlements["application-identifier"] as? String,
              let separator = identifier.firstIndex(of: "."), separator != identifier.startIndex,
              identifier[identifier.index(after: separator)...] == bundleID,
              let expiry = fields["ExpirationDate"] as? Date, expiry.timeIntervalSinceReferenceDate.isFinite
        else { return nil }
        return expiry
    }

    // Reads only the encapsulated property list of a definite-length CMS SignedData.
    // iOS decides whether the signature is valid. This date is a reminder hint.
    private struct DERReader {
        let bytes: [UInt8]
        let end: Int
        var offset: Int

        init(_ bytes: [UInt8], range: Range<Int>? = nil) {
            let range = range ?? bytes.indices
            self.bytes = bytes
            self.offset = range.lowerBound
            self.end = range.upperBound
        }

        var isAtEnd: Bool { offset == end }
        var data: Data { Data(bytes[offset..<end]) }

        mutating func readOID(endingWith lastByte: UInt8) -> Bool {
            guard let oid = read(0x06) else { return false }
            return bytes[oid.offset..<oid.end].elementsEqual([
                0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, lastByte
            ])
        }

        mutating func read(_ tag: UInt8) -> DERReader? {
            guard end - offset >= 2, bytes[offset] == tag else { return nil }
            var length = Int(bytes[offset + 1])
            offset += 2
            if length >= 0x80 {
                let lengthByteCount = length & 0x7f
                guard (1...4).contains(lengthByteCount), lengthByteCount <= end - offset,
                      bytes[offset] != 0 else { return nil }
                length = 0
                for byte in bytes[offset..<(offset + lengthByteCount)] {
                    length = (length << 8) | Int(byte)
                }
                guard length >= 128 else { return nil }
                offset += lengthByteCount
            }
            guard length <= end - offset else { return nil }
            let value = DERReader(bytes, range: offset..<(offset + length))
            offset += length
            return value
        }
    }
}
