import Foundation

enum BackupError: LocalizedError {
    case unsupportedVersion(Int), invalidData
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v): return "Il backup usa la versione dati \(v). Aggiorna Pivot: il file originale non è stato modificato."
        case .invalidData: return "Questo file non è un backup valido di Pivot. Nessun dato è stato sostituito."
        }
    }
}

enum BackupCodec {
    static func encode(_ data: AppData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(data)
    }
    static func decode(_ bytes: Data) throws -> AppData {
        let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        guard let version = object?["schemaVersion"] as? Int else { throw BackupError.invalidData }
        guard version == 1 else { throw BackupError.unsupportedVersion(version) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try decoder.decode(AppData.self, from: bytes)
        guard data.records.allSatisfy({ $0.key == $0.value.id }),
              data.income.allSatisfy({ $0.amountCents >= 0 && $0.paidCents >= 0 && $0.paidCents <= $0.amountCents && $0.minutes > 0 }),
              data.moves.allSatisfy({ $0.proposedEnd > $0.proposedStart }),
              data.payments.allSatisfy({ payment in payment.amountCents > 0 && data.income.contains(where: { entry in entry.id == payment.incomeID }) }),
              data.income.allSatisfy({ entry in data.payments.filter { $0.incomeID == entry.id }.reduce(0) { $0 + $1.amountCents } == entry.paidCents }) else { throw BackupError.invalidData }
        return data
    }
}
