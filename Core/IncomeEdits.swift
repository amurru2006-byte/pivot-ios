import Foundation

struct IncomeEdit: Codable, Identifiable {
    var id = UUID()
    var incomeID: UUID
    var paymentID: UUID?
    var previousCents: Int
    var correctedCents: Int
    var editedAt: Date
}

enum IncomeEdits {
    enum Failure: Error { case missing, invalidAmount, belowReceived, inconsistentReceipts }

    // Changing the compensation never invents a receipt/refund or changes the
    // original lesson/calendar occurrence. Corrections keep a local audit trail.
    static func compensation(incomeID: UUID, cents: Int, now: Date = Date(), data: inout AppData) throws {
        guard let index = data.income.firstIndex(where: { $0.id == incomeID }) else { throw Failure.missing }
        guard (0...100_000_000).contains(cents) else { throw Failure.invalidAmount }
        guard cents >= data.income[index].paidCents else { throw Failure.belowReceived }
        let previous = data.income[index].amountCents
        guard previous != cents else { return }
        data.income[index].amountCents = cents
        data.incomeEdits = (data.incomeEdits ?? []) + [IncomeEdit(incomeID: incomeID, previousCents: previous, correctedCents: cents, editedAt: now)]
    }

    // Correct just the selected receipt at its actual receipt date; other
    // receipts, annual opening balances and future lessons remain untouched.
    static func receipt(paymentID: UUID, cents: Int, now: Date = Date(), data: inout AppData) throws {
        guard let p = data.payments.firstIndex(where: { $0.id == paymentID }),
              let i = data.income.firstIndex(where: { $0.id == data.payments[p].incomeID }) else { throw Failure.missing }
        guard (1...100_000_000).contains(cents) else { throw Failure.invalidAmount }
        let linked = data.payments.filter { $0.incomeID == data.income[i].id }.reduce(0) { $0 + $1.amountCents }
        guard linked == data.income[i].paidCents else { throw Failure.inconsistentReceipts }
        let correctedTotal = linked - data.payments[p].amountCents + cents
        guard correctedTotal <= data.income[i].amountCents else { throw Failure.belowReceived }
        let previous = data.payments[p].amountCents
        guard previous != cents else { return }
        data.payments[p].amountCents = cents; data.income[i].paidCents = correctedTotal
        data.incomeEdits = (data.incomeEdits ?? []) + [IncomeEdit(incomeID: data.income[i].id, paymentID: paymentID,
                                                              previousCents: previous, correctedCents: cents, editedAt: now)]
    }
}
