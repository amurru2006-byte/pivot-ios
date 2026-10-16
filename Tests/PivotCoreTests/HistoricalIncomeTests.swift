import XCTest
@testable import PivotCore

final class HistoricalIncomeTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-01T12:00:00Z")!
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func data() -> AppData {
        var data = AppData()
        data.clients = [Client(name: "Contatto A Test", rateCents: 1200), Client(name: "Contatto B Test", rateCents: 1800)]
        data.ledger = AnnualLedger(openingCents: ["2026": 2500])
        return data
    }
    private func event(_ id: String = "historical-test", day: String = "2026-03-01", minutes: Int = 60) -> CalendarItem {
        let start = date(day + "T10:00:00Z")
        return CalendarItem(id: id, eventIdentifier: id, calendarIdentifier: "work-test", calendarTitle: "Lavoro",
            title: "Lezione di prova", start: start, end: start.addingTimeInterval(Double(minutes) * 60),
            location: "", notes: "", colorHex: "123456", isAllDay: false, writable: true, kind: .tutoring)
    }
    private func quote(_ event: CalendarItem, data: AppData, client: Int = 0) throws -> HistoricalIncome.Quote {
        try HistoricalIncome.quote(event, clientID: data.clients[client].id, year: 2026, now: now, data: data)
    }
    private func balance(_ data: AppData) throws -> SavingsBalance {
        try SavingsAccounting.balance(XCTUnwrap(data.savingsBudget), payments: data.payments)
    }

    func testRatesForAllContactsAndOpeningAbsorptionDoNotDuplicateFunds() throws {
        var data = data(); let a = event("a"), b = event("b", day: "2026-03-02", minutes: 120)
        let quotes = [try quote(a, data: data), try quote(b, data: data, client: 1)]
        let result = try HistoricalIncome.apply(Array(quotes.reversed()), freshEvents: [b, a], now: now, data: &data)
        XCTAssertEqual(result.lessons, 2); XCTAssertEqual(result.receiptsCents, 4800)
        XCTAssertEqual(result.openingAttributedCents, 2500); XCTAssertEqual(result.extraAnnualCents, 2300)
        XCTAssertEqual(data.income.map(\.amountCents), [1200, 3600])
        XCTAssertEqual(data.income.compactMap { $0.historicalSource?.openingAttributedCents }, [1200, 1300])
        XCTAssertEqual(data.ledger?.total(year: 2026, payments: data.payments), 4800)
        XCTAssertEqual(data.ledger?.openingCents["2026"], 0)
        XCTAssertEqual(try balance(data).freeCents, 2500)
        XCTAssertTrue(data.payments.allSatisfy { $0.excludedFromBudget == true && $0.date == nil && $0.year == 2026 })
        XCTAssertEqual(data.records.count, 2); XCTAssertTrue(data.records.values.allSatisfy { $0.actualStart == nil && $0.actualEnd == nil })
    }

    func testPartialBackfillLeavesUnusedOpeningAndDoesNotInventSmallerLesson() throws {
        var data = data(); let item = event()
        try HistoricalIncome.apply([quote(item, data: data)], freshEvents: [item], now: now, data: &data)
        XCTAssertEqual(data.income[0].amountCents, 1200); XCTAssertEqual(data.ledger?.openingCents["2026"], 1300)
        XCTAssertEqual(data.ledger?.total(year: 2026, payments: data.payments), 2500)
        XCTAssertEqual(try balance(data).freeCents, 2500)
    }

    func testRepeatingImportOrChangingCalendarIdentifierDoesNotDuplicateReceipt() throws {
        var data = data(); var item = event(); item.recurring = false
        let quotes = [try quote(item, data: data)]
        try HistoricalIncome.apply(quotes, freshEvents: [item], now: now, data: &data)
        XCTAssertEqual(try HistoricalIncome.apply(quotes, freshEvents: [item], now: now, data: &data).lessons, 0)
        var other = item; other.id = "new-id"; other.eventIdentifier = "new-id"
        other.calendarIdentifier = "other-account"; item.externalIdentifier = "test-shared-uid"
        other.externalIdentifier = "test-shared-uid"
        data.income[0].historicalSource?.event = item
        data.records.removeAll() // Provenance itself is sufficient after a record cleanup.
        XCTAssertNotNil(HistoricalIncome.existingEntry(for: other, data: data))
        XCTAssertEqual(data.income.count, 1); XCTAssertEqual(data.payments.count, 1)
    }

    func testAlreadyRegisteredUnpaidLessonIsNotOverwrittenOrSettled() throws {
        var data = data(); let item = event(), client = data.clients[0]
        let entry = IncomeEntry(clientID: client.id, clientName: client.name, date: item.end, minutes: 60,
            amountCents: 1200, paidCents: 700, calendarEventID: item.id)
        data.income = [entry]; data.payments = [.init(incomeID: entry.id, clientName: client.name, date: item.end, amountCents: 700)]
        XCTAssertThrowsError(try quote(item, data: data))
        XCTAssertEqual(data.income[0].outstandingCents, 500); XCTAssertNil(data.savingsBudget)
    }

    func testUnlinkedSameDayAndCombinedWeeklyReceiptRequireReview() throws {
        var data = data(); let item = event(), client = data.clients[0]
        data.income = [.init(clientID: client.id, clientName: client.name, date: item.end, minutes: 60, amountCents: 1200)]
        XCTAssertThrowsError(try quote(item, data: data))
        data.income[0].date = item.end.addingTimeInterval(-86400)
        data.income[0].paidCents = 1200; data.income[0].notes = "Saldo della settimana"
        XCTAssertThrowsError(try quote(item, data: data))
    }

    func testExplicitDiaryAnswersAreNotOverwritten() throws {
        for status in [Completion.skipped, .partial, .running] {
            var data = data(); let item = event()
            data.records[item.id] = EventRecord(id: item.id, snapshot: item, status: status)
            XCTAssertThrowsError(try quote(item, data: data))
        }
        var data = data(); let item = event()
        data.records[item.id] = EventRecord(id: item.id, snapshot: item, tutoringAnswered: true)
        XCTAssertThrowsError(try quote(item, data: data))
    }

    func testCalendarChangeOrRateChangeRejectsWholeBatchWithoutInitializingBudget() throws {
        var data = data(); let a = event("a"), b = event("b", day: "2026-03-02")
        let quotes = [try quote(a, data: data), try quote(b, data: data)]
        var changed = b; changed.end.addTimeInterval(600)
        XCTAssertThrowsError(try HistoricalIncome.apply(quotes, freshEvents: [a, changed], now: now, data: &data))
        XCTAssertTrue(data.income.isEmpty); XCTAssertNil(data.savingsBudget)
        data.clients[0].rateCents = 1500
        XCTAssertThrowsError(try HistoricalIncome.apply(quotes, freshEvents: [a, b], now: now, data: &data))
        XCTAssertTrue(data.payments.isEmpty); XCTAssertEqual(data.ledger?.openingCents["2026"], 2500)
    }

    func testRejectsFutureAllDayWrongYearAndNonWorkEvents() {
        let data = data()
        var cases = [event(day: "2027-03-01"), event(day: "2025-03-01"), event(minutes: 481)]
        var allDay = event(); allDay.isAllDay = true; cases.append(allDay)
        var meal = event(); meal.kind = .meal; cases.append(meal)
        var invalid = event(); invalid.end = invalid.start; cases.append(invalid)
        for item in cases { XCTAssertThrowsError(try quote(item, data: data)) }
    }

    func testUnknownRateDoesNotUseAgeAreaOrCalendarTextAsTariff() {
        var data = data(); data.clients[0].rateCents = 0
        XCTAssertThrowsError(try quote(event(), data: data))
        XCTAssertThrowsError(try HistoricalIncome.quote(event(), clientID: UUID(), year: 2026, now: now, data: data))
    }

    func testNewNormalReceiptAfterBackfillIncreasesFundsButOldOnesDoNot() throws {
        var data = data(); let item = event()
        try HistoricalIncome.apply([quote(item, data: data)], freshEvents: [item], now: now, data: &data)
        let client = data.clients[0]
        let entry = IncomeEntry(clientID: client.id, clientName: client.name, date: now, minutes: 60, amountCents: 1200, paidCents: 1200)
        data.income.append(entry); data.payments.append(.init(incomeID: entry.id, clientName: client.name, date: now, amountCents: 1200))
        XCTAssertEqual(try balance(data).freeCents, 3700)
    }

    func testYearOnlyReceiptRoundTripAndMonthlyDailyReportNeverInventDate() throws {
        var data = data(); let item = event()
        try HistoricalIncome.apply([quote(item, data: data)], freshEvents: [item], now: now, data: &data)
        let decoded = try BackupCodec.decode(BackupCodec.encodeCompact(data))
        XCTAssertNil(decoded.payments[0].date); XCTAssertEqual(decoded.payments[0].year, 2026)
        XCTAssertFalse(decoded.payments[0].occurred(from: item.start, to: now))
        let xlsx = LedgerExcel.make(data: data, year: 2026)
        XCTAssertTrue(String(decoding: xlsx, as: UTF8.self).contains("Data non nota"))
    }

    func testReceiptWithoutDateOrYearAndConflictingYearAreInvalidBackups() throws {
        var data = data(); let item = event()
        try HistoricalIncome.apply([quote(item, data: data)], freshEvents: [item], now: now, data: &data)
        data.payments[0].receivedYear = nil
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encodeCompact(data)))
        data.payments[0].receivedYear = 2026; data.payments[0].date = date("2025-01-01T12:00:00Z")
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encodeCompact(data)))
    }

    func testLegacyDatedReceiptStillDecodesWithoutNewOptionalFields() throws {
        var data = data(); let client = data.clients[0], item = event()
        let entry = IncomeEntry(clientID: client.id, clientName: client.name, date: item.end, minutes: 60, amountCents: 1200, paidCents: 1200)
        data.income = [entry]; data.payments = [.init(incomeID: entry.id, clientName: client.name, date: item.end, amountCents: 1200)]
        let restored = try BackupCodec.decode(BackupCodec.encodeCompact(data))
        XCTAssertEqual(restored.payments[0].date, item.end); XCTAssertNil(restored.payments[0].receivedYear)
        XCTAssertEqual(restored.payments[0].year, 2026); XCTAssertNil(restored.income[0].historicalSource)
    }

    func testDuplicateCandidateAndInvalidSourceAreRejected() throws {
        var data = data(); let item = event(), q = try quote(event(), data: data)
        XCTAssertThrowsError(try HistoricalIncome.apply([q, q], freshEvents: [item], now: now, data: &data))
        XCTAssertNil(data.savingsBudget)
        try HistoricalIncome.apply([q], freshEvents: [item], now: now, data: &data)
        data.payments[0].excludedFromBudget = nil
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encodeCompact(data)))
    }
}
