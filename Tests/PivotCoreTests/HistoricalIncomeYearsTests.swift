import XCTest
@testable import PivotCore

final class HistoricalIncomeYearsTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-18T18:00:00Z")!
    private func event(year: Int, id: String? = nil) -> CalendarItem {
        let start = PivotDate.calendar.date(from: DateComponents(year: year, month: 3, day: 12, hour: 15))!
        let key = id ?? "synthetic-lesson-\(year)"
        return CalendarItem(id: key, eventIdentifier: key, calendarIdentifier: "synthetic-work", calendarTitle: "Lavoro",
            title: "Lezione sintetica", start: start, end: start.addingTimeInterval(7200),
            location: "", notes: "", colorHex: "123456", isAllDay: false, writable: true, kind: .tutoring)
    }
    private func data() -> AppData {
        var value = AppData()
        value.clients = [Client(name: "Contatto Test", rateCents: 1500)]
        value.ledger = AnnualLedger(openingCents: ["2026": 22_000])
        return value
    }
    private func quote(_ event: CalendarItem, year: Int, rate: Int?, data: AppData) throws -> HistoricalIncome.Quote {
        try HistoricalIncome.quote(event, clientID: data.clients[0].id, year: year, now: now, data: data, confirmedRateCents: rate)
    }

    func testPastYearNeedsExplicitRateRatherThanAssumingCurrentProfileRate() throws {
        let value = data(), item = event(year: 2025)
        XCTAssertThrowsError(try quote(item, year: 2025, rate: nil, data: value)) { error in
            guard case HistoricalIncomeError.historicalRateRequired = error else { return XCTFail("Historical rate must be confirmed") }
        }
        let reviewed = try quote(item, year: 2025, rate: 1000, data: value)
        XCTAssertEqual(reviewed.amountCents, 2000)
        XCTAssertEqual(reviewed.rateCents, 1000)
        XCTAssertEqual(value.clients[0].rateCents, 1500)
    }

    func testSeveralYearsKeepAnnualTotalsOpeningFundsAndProfileSeparate() throws {
        var value = data()
        let a = event(year: 2024), b = event(year: 2025)
        let reviewed = [try quote(a, year: 2024, rate: 1000, data: value), try quote(b, year: 2025, rate: 1200, data: value)]
        let result = try HistoricalIncome.apply(reviewed, freshEvents: [a, b], now: now, assumePaidOnActivityDate: true, data: &value)
        XCTAssertEqual(result.receiptsCents, 4400)
        XCTAssertEqual(result.openingAttributedCents, 0)
        XCTAssertEqual(value.ledger?.openingCents["2026"], 22_000)
        XCTAssertEqual(value.ledger?.total(year: 2024, payments: value.payments), 2000)
        XCTAssertEqual(value.ledger?.total(year: 2025, payments: value.payments), 2400)
        XCTAssertEqual(value.ledger?.total(year: 2026, payments: value.payments), 22_000)
        XCTAssertEqual(value.clients[0].rateCents, 1500)
        XCTAssertTrue(value.payments.allSatisfy { $0.excludedFromBudget == true })
        XCTAssertEqual(try SavingsAccounting.balance(XCTUnwrap(value.savingsBudget), payments: value.payments).freeCents, 22_000)
        XCTAssertEqual(try HistoricalIncome.apply(reviewed, freshEvents: [a, b], now: now, data: &value).lessons, 0)
        XCTAssertEqual(value.payments.count, 2)
        let restored = try BackupCodec.decode(BackupCodec.encodeCompact(value))
        XCTAssertEqual(restored.payments.compactMap(\.year).sorted(), [2024, 2025])
    }

    func testOpeningAllocationIsScopedToImportedYearNotAnotherYearsAggregate() throws {
        var value = data()
        value.ledger?.openingCents["2025"] = 1500
        let item = event(year: 2025), reviewed = try quote(item, year: 2025, rate: 1000, data: value)
        let result = try HistoricalIncome.apply([reviewed], freshEvents: [item], now: now, data: &value)
        XCTAssertEqual(result.openingAttributedCents, 1500)
        XCTAssertEqual(result.extraAnnualCents, 500)
        XCTAssertEqual(value.ledger?.openingCents["2026"], 22_000)
        XCTAssertEqual(value.ledger?.total(year: 2025, payments: value.payments), 2000)
        XCTAssertEqual(try SavingsAccounting.balance(XCTUnwrap(value.savingsBudget), payments: value.payments).freeCents, 23_500)
    }

    func testConfirmedHistoricalRateSurvivesCurrentRateChangeWithoutOverwritingIt() throws {
        var value = data()
        let item = event(year: 2025), reviewed = try quote(item, year: 2025, rate: 1000, data: value)
        value.clients[0].rateCents = 2000
        try HistoricalIncome.apply([reviewed], freshEvents: [item], now: now, data: &value)
        XCTAssertEqual(value.income[0].amountCents, 2000)
        XCTAssertEqual(value.income[0].historicalSource?.rateCents, 1000)
        XCTAssertEqual(value.clients[0].rateCents, 2000)
        XCTAssertThrowsError(try quote(item, year: 2025, rate: 1000, data: value))
    }

    func testUnpaidExistingLessonInPreviousYearNeverGetsSettledByBackfill() throws {
        var value = data(); let item = event(year: 2025), client = value.clients[0]
        value.income = [IncomeEntry(clientID: client.id, clientName: client.name, date: item.end, minutes: 120,
            amountCents: 2000, paidCents: 1500, calendarEventID: item.id)]
        XCTAssertThrowsError(try quote(item, year: 2025, rate: 1000, data: value))
        XCTAssertEqual(value.income[0].outstandingCents, 500)
        XCTAssertTrue(value.payments.isEmpty)
        XCTAssertNil(value.savingsBudget)
    }

    func testWrongYearInvalidRateAndNonFiniteDatesAreRejectedBeforeMoneyWrites() throws {
        let value = data(), item = event(year: 2025)
        XCTAssertThrowsError(try quote(item, year: 2024, rate: 1000, data: value))
        XCTAssertThrowsError(try quote(item, year: 2025, rate: 0, data: value))
        XCTAssertThrowsError(try quote(item, year: 2025, rate: 100_000_001, data: value))
        XCTAssertFalse(HistoricalIncome.validYear(1899, now: now))
        XCTAssertFalse(HistoricalIncome.validYear(2027, now: now))
        XCTAssertFalse(HistoricalIncome.validYear(2025, now: Date(timeIntervalSinceReferenceDate: .nan)))
        var broken = item; broken.start = Date(timeIntervalSinceReferenceDate: .nan)
        XCTAssertFalse(HistoricalIncome.isEligible(broken, year: 2025, now: now))
    }
}
