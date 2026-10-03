import Foundation

struct AnnualLedger: Codable {
    // Opening aggregates are user data, not invented individual receipts.
    var openingCents: [String: Int] = [:]
    var referenceCents: Int = 500_000
    var warningMarginCents: Int = 50_000
    func total(year: Int, payments: [Payment]) -> Int {
        (openingCents[String(year)] ?? 0) + payments.filter { PivotDate.calendar.component(.year, from: $0.date) == year }.reduce(0) { $0 + $1.amountCents }
    }
    mutating func setOpeningTotal(_ total: Int, year: Int, payments: [Payment]) {
        let recorded = payments.filter { PivotDate.calendar.component(.year, from: $0.date) == year }.reduce(0) { $0 + $1.amountCents }
        openingCents[String(year)] = max(0, total - recorded)
    }
    func warningProgress(total: Int) -> Double? {
        guard referenceCents > 0, warningMarginCents > 0, total >= referenceCents - warningMarginCents else { return nil }
        return min(1, max(0, Double(total - (referenceCents - warningMarginCents)) / Double(warningMarginCents)))
    }
    func band(total: Int) -> String? {
        guard warningProgress(total: total) != nil else { return nil }
        return total >= referenceCents ? "reference" : "approaching"
    }
    static let fiscalExplanation = "Non esiste un tetto universale di guadagni non dichiarabili. I 5.000 € sono una franchigia contributiva INPS solo per lavoro autonomo realmente occasionale, non un'esenzione fiscale. Per attività abituale può servire partita IVA anche sotto questa cifra. Il contatore usa gli incassi registrati, senza calcolare spese, altri redditi o imposte: verifica la tua situazione con un CAF o commercialista."
    static let sourceURL = "https://www.inps.it/it/it/dettaglio-approfondimento.schede-informative.49893.i-contributi-dei-lavoratori-autonomi-occasionali.html"
}

enum TutoringLedger {
    // Repeated saves of the same calendar occurrence never generate a second lesson/payment.
    @discardableResult static func register(event: CalendarItem, record: inout EventRecord, client: Client, amountCents: Int, collectedCents: Int, paymentDate: Date, data: inout AppData) -> UUID? {
        guard [.tutoring, .work].contains(event.kind), amountCents >= 0, collectedCents >= 0, collectedCents <= amountCents else { return nil }
        if let existing = data.income.first(where: { $0.id == record.incomeID || $0.calendarEventID == event.id }) {
            record.incomeID = existing.id; record.tutoringAnswered = true
            return existing.id
        }
        record.tutoringAnswered = true
        guard amountCents > 0 else { return nil }
        let entry = IncomeEntry(clientID: client.id, clientName: client.name, date: record.actualEnd ?? event.end, minutes: max(1, record.activeMinutes > 0 ? record.activeMinutes : event.durationMinutes), amountCents: amountCents, paidCents: collectedCents, notes: record.notes, calendarEventID: event.id)
        if !data.clients.contains(where: { $0.id == client.id }) { data.clients.append(client) }
        data.income.append(entry)
        if collectedCents > 0 { data.payments.append(.init(incomeID: entry.id, clientName: client.name, date: paymentDate, amountCents: collectedCents)) }
        record.incomeID = entry.id
        return entry.id
    }
}
