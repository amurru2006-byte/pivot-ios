import Foundation

struct HistoricalIncomeSource: Codable, Equatable {
    var event: CalendarItem
    var rateCents: Int
    var openingAttributedCents: Int
    var receivedYear: Int
    var receiptID: UUID
    var importedAt: Date
}

enum HistoricalIncomeError: LocalizedError {
    case ineligible, alreadyRecorded, reviewRequired, missingClient, changed, invalid
    var errorDescription: String? {
        switch self {
        case .ineligible: return "Seleziona una lezione conclusa nell’anno scelto, con una durata valida."
        case .alreadyRecorded: return "Questa attività è già nel registro."
        case .reviewRequired: return "C’è già una registrazione o un pagamento che potrebbe comprendere questa lezione. Verifica prima di importarla."
        case .missingClient: return "Conferma il contatto e la sua tariffa prima di importare."
        case .changed: return "Calendario o registro modificati: ricarica l’anteprima prima di confermare."
        case .invalid: return "Ricostruzione non valida. Nessun importo è stato modificato."
        }
    }
}

/// Local, explicit backfill. Calendar presence alone never causes a money write.
enum HistoricalIncome {
    struct Quote: Equatable, Identifiable {
        var id: String { event.id }
        let event: CalendarItem
        let clientID: UUID
        let clientName: String
        let rateCents: Int
        let minutes: Int
        let amountCents: Int
        let year: Int
    }
    struct Result: Equatable {
        var lessons = 0
        var receiptsCents = 0
        var openingAttributedCents = 0
        var extraAnnualCents: Int { receiptsCents - openingAttributedCents }
    }

    static func isEligible(_ event: CalendarItem, year: Int, now: Date) -> Bool {
        (2026...9999).contains(year) && year <= PivotDate.calendar.component(.year, from: now)
            && [.tutoring, .work].contains(event.kind) && !event.isAllDay
            && event.end > event.start && event.end <= now
            && event.end.timeIntervalSince(event.start) <= 8 * 3600
            && PivotDate.calendar.component(.year, from: event.start) == year
            && PivotDate.calendar.component(.year, from: event.end) == year
    }

    static func existingEntry(for event: CalendarItem, data: AppData) -> IncomeEntry? {
        let records = data.records.values.filter { EventCoalescer.savedOccurrence($0.snapshot, event) }
        let ids = Set(records.compactMap(\.incomeID))
        return data.income.first { entry in
            entry.calendarEventID == event.id || ids.contains(entry.id)
                || (entry.historicalSource.map { EventCoalescer.savedOccurrence($0.event, event) } ?? false)
        }
    }

    static func quote(_ event: CalendarItem, clientID: UUID, year: Int, now: Date, data: AppData) throws -> Quote {
        guard isEligible(event, year: year, now: now) else { throw HistoricalIncomeError.ineligible }
        guard existingEntry(for: event, data: data) == nil else { throw HistoricalIncomeError.alreadyRecorded }
        guard let client = data.clients.first(where: { $0.id == clientID }),
              (1...100_000_000).contains(client.rateCents) else { throw HistoricalIncomeError.missingClient }
        let records = data.records.values.filter { EventCoalescer.savedOccurrence($0.snapshot, event) }
        // Explicit diary answers are not overwritten by "all past lessons paid".
        guard !records.contains(where: { [.skipped, .partial, .running].contains($0.status)
            || $0.tutoringAnswered == true || $0.actualStart != nil || $0.actualEnd != nil || $0.activeMinutes > 0 }) else {
            throw HistoricalIncomeError.reviewRequired
        }
        let sameClient = data.income.filter { $0.clientID == clientID }
        let interval = StudentPayments.week(containing: event.start)
        guard !sameClient.contains(where: { entry in
            let unlinkedSameDay = entry.calendarEventID == nil && PivotDate.calendar.isDate(entry.date, inSameDayAs: event.end)
            let combinedReceipt = entry.paidCents > 0 && entry.date >= interval.start && entry.date < interval.end
                && (StudentPayments.timing(for: entry, data: data) == .weekly
                    || EventCoalescer.normalized(entry.notes).contains("settiman"))
            return unlinkedSameDay || combinedReceipt
        }) else { throw HistoricalIncomeError.reviewRequired }
        let minutes = event.durationMinutes
        // Positive bounded rates and <= 480 minutes cannot overflow Int64.
        let cents = Money.lessonAmount(rateCents: client.rateCents, minutes: minutes)
        guard (1...100_000_000).contains(cents) else { throw HistoricalIncomeError.invalid }
        return Quote(event: event, clientID: client.id, clientName: client.name,
                     rateCents: client.rateCents, minutes: minutes, amountCents: cents, year: year)
    }

    /// Re-evaluate against a fresh EventKit snapshot and latest store. Atomic on failure.
    /// Repeating an identical confirmed batch is harmless; no destructive deduplication.
    @discardableResult static func apply(_ quotes: [Quote], freshEvents: [CalendarItem], now: Date, data: inout AppData) throws -> Result {
        guard !quotes.isEmpty, quotes.count <= 10_000, Set(quotes.map(\.id)).count == quotes.count else { throw HistoricalIncomeError.invalid }
        var next = data
        var pending: [Quote] = []
        for expected in quotes {
            guard let fresh = freshEvents.first(where: { $0.id == expected.id }), fresh == expected.event else { throw HistoricalIncomeError.changed }
            if let existing = existingEntry(for: fresh, data: next) {
                guard let source = existing.historicalSource, source.event == expected.event,
                      existing.clientID == expected.clientID, source.rateCents == expected.rateCents,
                      source.receivedYear == expected.year, existing.minutes == expected.minutes,
                      existing.amountCents == expected.amountCents else { throw HistoricalIncomeError.changed }
                continue
            }
            guard try quote(fresh, clientID: expected.clientID, year: expected.year, now: now, data: next) == expected else { throw HistoricalIncomeError.changed }
            guard !pending.contains(where: { EventCoalescer.savedOccurrence($0.event, fresh) }) else { throw HistoricalIncomeError.invalid }
            pending.append(expected)
        }
        guard !pending.isEmpty else { return Result() }
        // Capture the original opening funds ONCE, before moving any of that
        // aggregate into detailed historical receipts. All imported receipts are
        // budget-excluded, including the share already covered by the aggregate.
        try SavingsAccounting.initialize(data: &next)
        var ledger = next.ledger ?? AnnualLedger()
        var result = Result()
        for item in pending.sorted(by: { $0.event.start == $1.event.start ? $0.id < $1.id : $0.event.start < $1.event.start }) {
            let yearKey = String(item.year)
            let covered = min(ledger.openingCents[yearKey, default: 0], item.amountCents)
            guard covered >= 0 else { throw HistoricalIncomeError.invalid }
            ledger.openingCents[yearKey, default: 0] -= covered
            let receiptID = UUID()
            let source = HistoricalIncomeSource(event: item.event, rateCents: item.rateCents,
                openingAttributedCents: covered, receivedYear: item.year, receiptID: receiptID, importedAt: now)
            let entry = IncomeEntry(clientID: item.clientID, clientName: item.clientName, date: item.event.end,
                minutes: item.minutes, amountCents: item.amountCents, paidCents: item.amountCents,
                calendarEventID: item.id, historicalSource: source)
            next.income.append(entry)
            next.payments.append(Payment(id: receiptID, incomeID: entry.id, clientName: item.clientName, date: nil,
                amountCents: item.amountCents, excludedFromBudget: true, receivedYear: item.year))
            // Keep any independent diary notes/ratings intact. Do not invent actual times.
            let recordID = next.records.values.first { EventCoalescer.savedOccurrence($0.snapshot, item.event) }?.id ?? item.id
            var record = next.records[recordID] ?? EventRecord(id: recordID, snapshot: item.event)
            record.status = .completed; record.incomeID = entry.id; record.tutoringAnswered = true
            record.updatedAt = now; next.records[recordID] = record
            let (receipts, overflow) = result.receiptsCents.addingReportingOverflow(item.amountCents)
            guard !overflow else { throw HistoricalIncomeError.invalid }
            result.lessons += 1; result.receiptsCents = receipts; result.openingAttributedCents += covered
        }
        next.ledger = ledger
        _ = try BackupCodec.decode(BackupCodec.encodeCompact(next))
        data = next
        return result
    }

    static func validate(_ data: AppData) throws {
        for entry in data.income {
            guard let source = entry.historicalSource else { continue }
            guard (1...100_000_000).contains(source.rateCents),
                  (0...100_000_000).contains(source.openingAttributedCents),
                  (2026...9999).contains(source.receivedYear),
                  source.event.end > source.event.start, !source.event.isAllDay,
                  source.event.id == entry.calendarEventID,
                  PivotDate.calendar.component(.year, from: source.event.start) == source.receivedYear else { throw BackupError.invalidData }
            // The imported receipt stays excluded after corrections. A later
            // genuine payment toward this activity is a different, normal receipt.
            guard data.payments.contains(where: { $0.id == source.receiptID && $0.incomeID == entry.id && $0.excludedFromBudget == true }) else { throw BackupError.invalidData }
        }
    }
}
