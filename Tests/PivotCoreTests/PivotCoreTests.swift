import XCTest
@testable import PivotCore

final class PivotCoreTests: XCTestCase {
    func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func event(_ id: String, start: String, end: String, kind: EventKind = .study) -> CalendarItem {
        CalendarItem(id: id, eventIdentifier: id, externalIdentifier: id, calendarIdentifier: "test", calendarTitle: "Test", title: "studio", start: date(start), end: date(end), location: "", notes: "", colorHex: "#00FF00", isAllDay: false, writable: true, kind: kind)
    }
    func testMoneyUsesCentsAndRejectsInvalidText() {
        XCTAssertEqual(Money.cents(from: "15,50"), 1550)
        XCTAssertEqual(Money.cents(from: "0.01"), 1)
        XCTAssertEqual(Money.lessonAmount(rateCents: 1500, minutes: 90), 2250)
        XCTAssertNil(Money.cents(from: "-1"))
        XCTAssertNil(Money.cents(from: "1,2,3"))
        XCTAssertNil(Money.cents(from: "abc"))
    }
    func testFullBackupRoundTripPreservesIncomeAndHistory() throws {
        let item = event("one", start: "2026-10-02T10:00:00+02:00", end: "2026-10-02T12:00:00+02:00")
        var data = AppData()
        var record = EventRecord(id: item.id, snapshot: item)
        record.status = .partial
        record.reason = "Impegno fisso"
        record.hungerAfter = 4
        data.records[item.id] = record
        let client = Client(name: "Studente test", rateCents: 1500)
        data.clients.append(client)
        let entry = IncomeEntry(clientID: client.id, clientName: client.name, date: item.start, minutes: 60, amountCents: 1500, paidCents: 500)
        data.income.append(entry)
        data.payments.append(.init(incomeID: entry.id, clientName: client.name, date: item.end, amountCents: 500))
        let restored = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertEqual(restored.installationID, data.installationID)
        XCTAssertEqual(restored.income.first?.outstandingCents, 1000)
        XCTAssertEqual(restored.payments.first?.amountCents, 500)
        XCTAssertEqual(restored.records[item.id]?.reason, "Impegno fisso")
        XCTAssertEqual(restored.clients.first?.name, client.name)
    }
    func testUnsupportedOrInvalidBackupFailsInsteadOfResetting() {
        XCTAssertThrowsError(try BackupCodec.decode(Data("{\"schemaVersion\":99}".utf8)))
        XCTAssertThrowsError(try BackupCodec.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try BackupCodec.decode(Data("broken".utf8)))
    }
    func testInvalidPaymentTotalsAreRejected() throws {
        var data = AppData()
        let client = Client(name: "Test", rateCents: 1000)
        data.clients.append(client)
        data.income.append(.init(clientID: client.id, clientName: client.name, date: Date(), minutes: 60, amountCents: 1000, paidCents: 500))
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(data)))
    }
    func testRecoveryRequiresConfirmedTravel() {
        let item = event("one", start: "2026-10-02T10:00:00+02:00", end: "2026-10-02T12:00:00+02:00")
        XCTAssertTrue(Planner.recover(item, events: [], data: AppData(), now: date("2026-10-02T13:00:00+02:00")).isEmpty)
    }
    func testRecoveryRespectsEventsAndTravelAndDoesNotShortenStudy() {
        let item = event("one", start: "2026-10-02T10:00:00+02:00", end: "2026-10-02T12:00:00+02:00")
        let fixed = event("fixed", start: "2026-10-02T15:00:00+02:00", end: "2026-10-02T17:00:00+02:00", kind: .tutoring)
        var data = AppData()
        var rule = EventRule.defaultRule(for: item)
        rule.travelBeforeMinutes = 30
        rule.travelAfterMinutes = 30
        rule.travelConfirmed = true
        data.rules[item.id] = rule
        let suggestions = Planner.recover(item, events: [fixed], data: data, now: date("2026-10-02T13:00:00+02:00"), days: 1)
        XCTAssertEqual(suggestions.first?.start, date("2026-10-02T17:30:00+02:00"))
        XCTAssertEqual(suggestions.first?.end, date("2026-10-02T19:30:00+02:00"))
    }
    func testFixedEventsNeverGetRecoveryProposals() {
        let item = event("one", start: "2026-10-02T10:00:00+02:00", end: "2026-10-02T12:00:00+02:00", kind: .tutoring)
        var data = AppData()
        var rule = EventRule.defaultRule(for: item)
        rule.travelConfirmed = true
        data.rules[item.id] = rule
        XCTAssertTrue(Planner.recover(item, events: [], data: data, now: date("2026-10-02T13:00:00+02:00")).isEmpty)
    }
    func testRecurringOccurrencesHaveIndependentRecords() {
        let a = event("repeat|one", start: "2026-10-02T10:00:00+02:00", end: "2026-10-02T12:00:00+02:00")
        let b = event("repeat|two", start: "2026-10-03T10:00:00+02:00", end: "2026-10-03T12:00:00+02:00")
        var data = AppData()
        var record = EventRecord(id: a.id, snapshot: a)
        record.status = .completed
        data.records[a.id] = record
        XCTAssertNil(data.records[b.id])
    }
    func testReportDistinguishesMissingAnswersAndPaymentDate() {
        let item = event("one", start: "2026-10-02T10:00:00+02:00", end: "2026-10-02T12:00:00+02:00")
        let text = Report.day(item.start, events: [item], data: AppData())
        XCTAssertTrue(text.contains("Mancano sveglia reale"))
        XCTAssertTrue(text.contains("Eventi da compilare: 1"))
    }
    func testRomeDSTCalendarDayKeepsLocalDate() {
        XCTAssertEqual(PivotDate.key(date("2026-10-25T00:30:00+02:00")), "2026-10-25")
        XCTAssertEqual(PivotDate.key(date("2026-10-25T23:30:00+01:00")), "2026-10-25")
    }
}
