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
        var data = try decoder.decode(AppData.self, from: bytes)
        // Reclassify only legacy social snapshots; preserve IDs, answers and money.
        for id in Array(data.records.keys) {
            if var record = data.records[id], record.snapshot.kind == .social || EventCoalescer.normalized(record.snapshot.calendarTitle) == "lavoro" {
                let kind = EventKind.classify(title: record.snapshot.title, calendar: record.snapshot.calendarTitle)
                if kind == .partner || kind == .friends || kind == .tutoring { record.snapshot.kind = kind; data.records[id] = record }
            }
        }
        for index in data.moves.indices where data.moves[index].source.kind == .social {
            let item = data.moves[index].source
            let kind = EventKind.classify(title: item.title, calendar: item.calendarTitle)
            if kind == .partner || kind == .friends { data.moves[index].source.kind = kind }
        }
        guard data.records.allSatisfy({ $0.key == $0.value.id }),
              data.income.allSatisfy({ $0.amountCents >= 0 && $0.paidCents >= 0 && $0.paidCents <= $0.amountCents && $0.minutes > 0 }),
              data.moves.allSatisfy({ $0.proposedEnd > $0.proposedStart }),
              data.payments.allSatisfy({ payment in payment.amountCents > 0 && data.income.contains(where: { entry in entry.id == payment.incomeID }) }),
              data.income.allSatisfy({ entry in data.payments.filter { $0.incomeID == entry.id }.reduce(0) { $0 + $1.amountCents } == entry.paidCents }) else { throw BackupError.invalidData }
        return data
    }
}
