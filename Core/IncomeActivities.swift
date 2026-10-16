import Foundation

enum IncomeActivityKind: String, Codable, CaseIterable {
    case lesson, work, gift, other
    var label: String {
        switch self { case .lesson: return "Ripetizioni"; case .work: return "Lavoro"; case .gift: return "Regali e contributi"; case .other: return "Altro" }
    }
}
enum IncomeBilling: String, Codable, CaseIterable { case hourly, fixed }

enum ManualIncomeError: LocalizedError {
    case invalid, changed, conflict
    var errorDescription: String? {
        switch self {
        case .invalid: return "Controlla compenso, ricevuto e durata. Nessun importo è stato registrato."
        case .changed: return "Il contatto o la tariffa sono cambiati. Controlla i dati prima di confermare."
        case .conflict: return "Questa conferma esiste già con dati diversi. Non è stato aggiunto un doppione."
        }
    }
}

enum ManualIncome {
    @discardableResult static func register(id: UUID, client: Client, date: Date, minutes: Int,
        amountCents: Int, receivedCents: Int, paymentDate: Date, notes: String,
        timing: PaymentTiming = .everyLesson, promisedDate: Date? = nil,
        activity: IncomeActivityKind? = nil, billing: IncomeBilling? = nil, data: inout AppData) throws -> UUID {
        guard data.clients.first(where: { $0.id == client.id }) == client else { throw ManualIncomeError.changed }
        let kind = activity ?? client.activityKind
        let mode: IncomeBilling = kind == .gift ? .fixed : kind == .lesson ? .hourly : billing ?? client.billingMode
        let hasDuration = kind == .lesson || mode == .hourly
        let duration = hasDuration ? minutes : 0
        guard (1...100_000_000).contains(amountCents), (0...amountCents).contains(receivedCents),
              (!hasDuration || (1...480).contains(minutes)),
              date.timeIntervalSinceReferenceDate.isFinite, paymentDate.timeIntervalSinceReferenceDate.isFinite,
              timing != .chosenDate || promisedDate != nil else { throw ManualIncomeError.invalid }
        if let existing = data.income.first(where: { $0.id == id }) {
            let receipts = data.payments.filter { $0.incomeID == id }
            guard existing.clientID == client.id, existing.date == date, existing.minutes == duration,
                  existing.amountCents == amountCents, existing.paidCents == receivedCents,
                  existing.notes == notes, existing.activityKind == kind,
                  existing.billing == mode, existing.paymentTiming == timing,
                  existing.promisedPaymentDate == promisedDate,
                  (receivedCents == 0 ? receipts.isEmpty : receipts.count == 1 && receipts[0].date == paymentDate && receipts[0].amountCents == receivedCents) else { throw ManualIncomeError.conflict }
            return id
        }
        var next = data
        next.income.append(IncomeEntry(id: id, clientID: client.id, clientName: client.name, date: date,
            minutes: duration, amountCents: amountCents, paidCents: receivedCents, notes: notes,
            paymentTiming: timing, promisedPaymentDate: promisedDate, activity: kind, billing: mode))
        if receivedCents > 0 { next.payments.append(Payment(incomeID: id, clientName: client.name, date: paymentDate, amountCents: receivedCents)) }
        _ = try BackupCodec.decode(BackupCodec.encodeCompact(next))
        data = next
        return id
    }
}

enum IncomeAnalytics {
    enum Period { case all, year(Int), month(year: Int, month: Int) }
    struct Month: Identifiable {
        var id: Int
        var cents: Int
        var euros: Double { Double(cents) / 100 }
    }
    static func receipts(clientID: UUID, data: AppData) -> [Payment] {
        let ids = Set(data.income.filter { $0.clientID == clientID }.map(\.id))
        return data.payments.filter { ids.contains($0.incomeID) }
    }
    private static func sum(_ values: [Int]) throws -> Int {
        var total = 0
        for value in values {
            let (next, overflow) = total.addingReportingOverflow(value)
            guard !overflow, value >= 0 else { throw ManualIncomeError.invalid }
            total = next
        }
        return total
    }
    static func total(_ payments: [Payment], period: Period) throws -> Int {
        let filtered: [Payment]
        switch period {
        case .all: filtered = payments
        case .year(let year): filtered = payments.filter { $0.year == year }
        case .month(let year, let month):
            guard (1...12).contains(month), let start = PivotDate.calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let end = PivotDate.calendar.date(byAdding: .month, value: 1, to: start) else { throw ManualIncomeError.invalid }
            filtered = payments.filter { $0.occurred(from: start, to: end) }
        }
        return try sum(filtered.map(\.amountCents))
    }
    static func outstanding(clientID: UUID, data: AppData) throws -> Int {
        try sum(data.income.filter { $0.clientID == clientID }.map(\.outstandingCents))
    }
    static func months(year: Int, payments: [Payment]) throws -> [Month] {
        try (1...12).map { .init(id: $0, cents: try total(payments, period: .month(year: year, month: $0))) }
    }
    static func undated(year: Int, payments: [Payment]) throws -> Int {
        try sum(payments.filter { $0.date == nil && $0.year == year }.map(\.amountCents))
    }
}
