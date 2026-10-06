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
    static func encodeCompact(_ data: AppData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(data)
    }
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
        try StudyFiles.validateBackup(data)
        try data.training?.validate()
        guard (data.contextAnswers ?? []).allSatisfy({ answer in
                  answer.travelMinutes.map { (0...1440).contains($0) } ?? true
              }), (data.activityDrafts ?? [:]).allSatisfy({ pair in
                  pair.key == pair.value.record.id && (pair.value.record.cardio?.isValid ?? true)
              }) else { throw BackupError.invalidData }
        guard data.records.values.allSatisfy({ $0.cardio?.isValid ?? true }),
              data.checkIns.values.allSatisfy({ check in
                  guard let sleep = check.sleep else { return true }
                  return (sleep.durationSeconds.map { (0...172800).contains($0) } ?? true)
                      && (sleep.score.map { (0...100).contains($0) } ?? true)
                      && (sleep.awakenings.map { (0...1000).contains($0) } ?? true)
                      && (sleep.interruptionSeconds.map { (0...172800).contains($0) } ?? true)
              }) else { throw BackupError.invalidData }
        // Reclassify only legacy social snapshots; preserve IDs, answers and money.
        for id in Array(data.records.keys) {
            if var record = data.records[id], record.snapshot.kind == .social || EventCoalescer.normalized(record.snapshot.calendarTitle) == "lavoro" {
                let kind = EventKind.classify(title: record.snapshot.title, calendar: record.snapshot.calendarTitle)
                if kind == .partner || kind == .friends || kind == .tutoring || kind == .work { record.snapshot.kind = kind; data.records[id] = record }
            }
        }
        for index in data.moves.indices where data.moves[index].source.kind == .social {
            let item = data.moves[index].source
            let kind = EventKind.classify(title: item.title, calendar: item.calendarTitle)
            if kind == .partner || kind == .friends { data.moves[index].source.kind = kind }
        }
        if let ledger = data.ledger {
            guard ledger.referenceCents == 500_000, ledger.warningMarginCents == 50_000,
                  ledger.openingCents.allSatisfy({ pair in (Int(pair.key).map { (1900...9999).contains($0) } ?? false) && pair.value >= 0 }) else { throw BackupError.invalidData }
        }
        guard Set(data.income.map(\.id)).count == data.income.count,
              Set(data.payments.map(\.id)).count == data.payments.count,
              Set(data.clients.map(\.id)).count == data.clients.count,
              data.records.allSatisfy({ $0.key == $0.value.id }),
              data.income.allSatisfy({ $0.amountCents >= 0 && $0.paidCents >= 0 && $0.paidCents <= $0.amountCents && $0.minutes > 0 && ($0.paymentTiming != .chosenDate || $0.promisedPaymentDate != nil) }),
              data.moves.allSatisfy({ $0.proposedEnd > $0.proposedStart }),
              data.payments.allSatisfy({ payment in payment.amountCents > 0 && data.income.contains(where: { entry in entry.id == payment.incomeID }) }),
              data.income.allSatisfy({ entry in data.payments.filter { $0.incomeID == entry.id }.reduce(0) { $0 + $1.amountCents } == entry.paidCents }) else { throw BackupError.invalidData }
        if let reviews = data.workoutReviews {
            guard Set(reviews.map(\.id)).count == reviews.count,
                  reviews.allSatisfy({ $0.workout.end > $0.workout.start && $0.workout.durationSeconds > 0 && $0.workout.durationSeconds <= 86400 && ($0.workout.activeCalories.map { $0.isFinite && $0 >= 0 } ?? true) }) else { throw BackupError.invalidData }
        }
        if let draft = data.actualWorkoutDraft {
            guard draft.source.kind == .workout, draft.end.map({ $0 > draft.start }) ?? true else { throw BackupError.invalidData }
        }
        if let coach = data.coach {
            guard Set(coach.messages.map(\.id)).count == coach.messages.count,
                  Set(coach.options.map(\.id)).count == coach.options.count,
                  Set(coach.pendingCalendarChanges.map(\.id)).count == coach.pendingCalendarChanges.count,
                  Set(coach.memories.map(\.id)).count == coach.memories.count,
                  coach.options.allSatisfy({ !$0.moves.isEmpty && $0.moves.allSatisfy { $0.proposedEnd > $0.proposedStart } }),
                  coach.pendingCalendarChanges.allSatisfy({ $0.move.proposedEnd > $0.move.proposedStart }) else { throw BackupError.invalidData }
        }
        return data
    }
}
