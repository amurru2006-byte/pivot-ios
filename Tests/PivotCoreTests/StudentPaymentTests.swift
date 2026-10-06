import XCTest
@testable import PivotCore

final class StudentPaymentTests: XCTestCase {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func lesson(_ id: String, _ start: String, name: String = "Giulia Rossi") -> CalendarItem {
        let time = date(start)
        return CalendarItem(id: id, eventIdentifier: id, calendarIdentifier: "work", calendarTitle: "Lavoro", title: "Ripetizioni con " + name, start: time, end: time.addingTimeInterval(3600), location: "", notes: "", colorHex: "#ABCDEF", isAllDay: false, writable: true, kind: .tutoring)
    }
    private func unpaid(_ event: CalendarItem, client: Client, cents: Int = 1800, timing: PaymentTiming? = nil) -> IncomeEntry {
        IncomeEntry(clientID: client.id, clientName: client.name, date: event.end, minutes: 60, amountCents: cents, calendarEventID: event.id, paymentTiming: timing)
    }
    func testWeeklyPaymentHasOneReminderAtLastLessonNotAfterEachLesson() throws {
        let client = Client(name: "Giulia Rossi", rateCents: 1800, paymentCadence: .weekly)
        let monday = lesson("mon", "2026-10-05T16:00:00+02:00"), wednesday = lesson("wed", "2026-10-07T16:00:00+02:00"), friday = lesson("fri", "2026-10-09T16:00:00+02:00")
        var data = AppData(); data.clients = [client]; data.income = [unpaid(monday, client: client), unpaid(wednesday, client: client, cents: 2000)]
        let events = [monday, wednesday, friday]
        let due = try XCTUnwrap(StudentPayments.dues(planned: events, data: data).first)
        XCTAssertEqual(due.date, friday.end); XCTAssertEqual(due.amountCents, 3800); XCTAssertEqual(due.entryIDs.count, 2)
        XCTAssertFalse(due.isOverdue(at: wednesday.end))
        let requests = NotificationPlan.requests(events: events, data: data, now: wednesday.end)
        let payments = requests.filter { $0.destination == "payment" }
        XCTAssertEqual(payments.count, 1); XCTAssertEqual(payments[0].date, friday.end); XCTAssertEqual(payments[0].clientID, client.id.uuidString)
        XCTAssertTrue(payments[0].body.contains(Money.display(3800)))
    }
    func testWeeklyDeadlineFollowsChangedLastCalendarLesson() throws {
        let client = Client(name: "Giulia Rossi", rateCents: 1800, paymentCadence: .weekly)
        let first = lesson("first", "2026-10-05T16:00:00+02:00")
        var last = lesson("last", "2026-10-09T16:00:00+02:00")
        var data = AppData(); data.clients = [client]; data.income = [unpaid(first, client: client)]
        last.start = date("2026-10-10T18:00:00+02:00"); last.end = last.start.addingTimeInterval(3600)
        XCTAssertEqual(StudentPayments.dues(planned: [first, last], data: data).first?.date, last.end)
        var record = EventRecord(id: last.id, snapshot: last); record.status = .skipped; data.records[last.id] = record
        XCTAssertEqual(StudentPayments.dues(planned: [first, last], data: data).first?.date, first.end)
    }
    func testSingleLessonExceptionDoesNotChangeSavedWeeklyHabit() {
        let client = Client(name: "Giulia Rossi", rateCents: 1800, paymentCadence: .weekly)
        let item = lesson("one", "2026-10-05T16:00:00+02:00")
        var data = AppData(); data.clients = [client]
        let exception = unpaid(item, client: client, timing: .everyLesson), usual = unpaid(item, client: client)
        XCTAssertEqual(StudentPayments.timing(for: exception, data: data), .everyLesson)
        XCTAssertEqual(StudentPayments.timing(for: usual, data: data), .weekly)
        StudentPayments.remember(.nextLesson, for: client.id, data: &data)
        XCTAssertEqual(data.clients[0].paymentCadence, .weekly)
        StudentPayments.remember(.everyLesson, for: client.id, data: &data)
        XCTAssertEqual(StudentPayments.timing(for: usual, data: data), .everyLesson)
    }
    func testNextLessonBelongsToRecognizedStudentAndCanBeDeferredAgain() {
        let client = Client(name: "Giulia Rossi", rateCents: 1800)
        let first = lesson("first", "2026-10-05T16:00:00+02:00"), wrong = lesson("wrong", "2026-10-06T16:00:00+02:00", name: "Giovanna"), next = lesson("next", "2026-10-07T16:00:00+02:00"), later = lesson("later", "2026-10-09T16:00:00+02:00")
        var data = AppData(); data.clients = [client]; data.income = [unpaid(first, client: client, timing: .nextLesson)]
        let events = [first, wrong, next, later]
        XCTAssertEqual(StudentPayments.dues(planned: events, data: data).first?.date, next.end)
        data.income[0].paymentDeferralAfter = next.end
        XCTAssertEqual(StudentPayments.dues(planned: events, data: data).first?.date, later.end)
        XCTAssertNil(StudentPayments.dues(planned: [first, wrong], data: data).first?.date)
        XCTAssertFalse(NotificationPlan.requests(events: [first, wrong], data: data, now: first.end).contains { $0.destination == "payment" })
    }
    func testCombinedReceiptSettlesOldestAndPreservesPartialRemainder() throws {
        let client = Client(name: "Giulia Rossi", rateCents: 1800), other = Client(name: "Sara", rateCents: 1500)
        let first = lesson("first", "2026-10-05T16:00:00+02:00"), second = lesson("second", "2026-10-07T16:00:00+02:00")
        var data = AppData(); data.clients = [client, other]
        data.income = [unpaid(second, client: client, cents: 2100), unpaid(first, client: client), unpaid(first, client: other, cents: 1500)]
        let when = second.end
        XCTAssertTrue(StudentPayments.collect(clientID: client.id, cents: 2500, date: when, data: &data))
        XCTAssertEqual(data.income[0].paidCents, 700); XCTAssertEqual(data.income[1].paidCents, 1800); XCTAssertEqual(data.income[2].paidCents, 0)
        XCTAssertEqual(StudentPayments.balance(clientID: client.id, data: data), 1400)
        XCTAssertEqual(data.payments.reduce(0) { $0 + $1.amountCents }, 2500)
        XCTAssertTrue(data.payments.allSatisfy { $0.date == when }); XCTAssertEqual(data.payments.count, 2)
        XCTAssertNoThrow(try BackupCodec.decode(BackupCodec.encode(data)))
        XCTAssertTrue(StudentPayments.collect(clientID: client.id, cents: 1400, date: when, data: &data))
        XCTAssertFalse(StudentPayments.dues(planned: [first, second], data: data).contains { $0.clientID == client.id })
    }
    func testInvalidReceiptDoesNotMutateAmountsOrPayments() throws {
        let client = Client(name: "Giulia Rossi", rateCents: 1800), item = lesson("one", "2026-10-05T16:00:00+02:00")
        var data = AppData(); data.clients = [client]; data.income = [unpaid(item, client: client)]
        let before = try BackupCodec.encode(data)
        for cents in [-1, 0, 1801] { XCTAssertFalse(StudentPayments.collect(clientID: client.id, cents: cents, date: item.end, data: &data)) }
        XCTAssertEqual(try BackupCodec.encode(data), before)
    }
    func testChosenDateAndCadenceSurviveBackupWithoutInventingReceipts() throws {
        let client = Client(name: "Giulia Rossi", rateCents: 1800, paymentCadence: .weekly), item = lesson("one", "2026-10-05T16:00:00+02:00")
        var entry = unpaid(item, client: client, timing: .chosenDate)
        entry.promisedPaymentDate = date("2026-10-12T18:00:00+02:00")
        var data = AppData(); data.clients = [client]; data.income = [entry]
        let restored = try BackupCodec.decode(BackupCodec.encodeCompact(data))
        XCTAssertEqual(restored.clients[0].paymentCadence, .weekly)
        XCTAssertEqual(StudentPayments.dues(planned: [item], data: restored).first?.date, entry.promisedPaymentDate)
        XCTAssertEqual(restored.income[0].paidCents, 0); XCTAssertTrue(restored.payments.isEmpty)
        data.income[0].promisedPaymentDate = nil
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(data)))
    }
    func testOverdueBalanceGetsNextMorningReminderAndNoHourlyRepeats() {
        let client = Client(name: "Giulia Rossi", rateCents: 1800), item = lesson("old", "2026-10-05T16:00:00+02:00")
        var data = AppData(); data.clients = [client]; data.income = [unpaid(item, client: client)]
        let now = date("2026-10-07T19:00:00+02:00")
        let reminders = NotificationPlan.requests(events: [item], data: data, now: now).filter { $0.destination == "payment" }
        XCTAssertEqual(reminders.count, 1); XCTAssertEqual(reminders[0].date, date("2026-10-08T08:00:00+02:00"))
        XCTAssertTrue(reminders[0].body.contains("lezione precedente"))
        XCTAssertEqual(NotificationPlan.requests(events: [item], data: data, now: now.addingTimeInterval(60)).first { $0.destination == "payment" }?.id, reminders[0].id)
    }
    func testItalianWeekBoundaryIncludesFridayOfPreviousYearAndDST() {
        let interval = StudentPayments.week(containing: date("2027-01-01T16:00:00+01:00"))
        XCTAssertEqual(PivotDate.key(interval.start), "2026-12-28"); XCTAssertEqual(PivotDate.key(interval.end), "2027-01-04")
        let summerChange = StudentPayments.week(containing: date("2026-10-25T10:00:00+01:00"))
        XCTAssertEqual(PivotDate.key(summerChange.start), "2026-10-19"); XCTAssertEqual(PivotDate.key(summerChange.end), "2026-10-26")
    }
    func testSundayLessonEndingMondayBelongsToItsStartWeek() {
        let client = Client(name: "Giulia Rossi", rateCents: 1800, paymentCadence: .weekly)
        let overnight = lesson("night", "2026-10-11T23:30:00+02:00"), nextWeek = lesson("next", "2026-10-14T16:00:00+02:00")
        var data = AppData(); data.clients = [client]; data.income = [unpaid(overnight, client: client)]
        XCTAssertEqual(StudentPayments.dues(planned: [overnight, nextWeek], data: data).first?.date, overnight.end)
    }
    func testUnavailableWeeklyCalendarDoesNotInventDeadline() {
        let client = Client(name: "Giulia Rossi", rateCents: 1800, paymentCadence: .weekly), item = lesson("one", "2026-10-05T16:00:00+02:00")
        var data = AppData(); data.clients = [client]; data.income = [unpaid(item, client: client)]
        XCTAssertNil(StudentPayments.dues(planned: [], data: data).first?.date)
        XCTAssertFalse(NotificationPlan.requests(events: [], data: data, now: item.end).contains { $0.destination == "payment" })
    }
    func testLearnedWeeklyDeadlineRemainsOverdueAfterCalendarWindowMovesOn() throws {
        let client = Client(name: "Giulia Rossi", rateCents: 1800, paymentCadence: .weekly)
        let first = lesson("first", "2026-10-05T16:00:00+02:00"), last = lesson("last", "2026-10-09T16:00:00+02:00")
        var data = AppData(); data.clients = [client]; data.income = [unpaid(first, client: client)]
        let dues = StudentPayments.dues(planned: [first, last], data: data)
        XCTAssertTrue(StudentPayments.rememberDeadlines(dues, data: &data))
        XCTAssertFalse(StudentPayments.rememberDeadlines(dues, data: &data))
        let restored = try BackupCodec.decode(BackupCodec.encodeCompact(data))
        let historical = try XCTUnwrap(StudentPayments.dues(planned: [], data: restored).first)
        XCTAssertEqual(historical.date, last.end); XCTAssertTrue(historical.isOverdue(at: date("2026-11-01T10:00:00+01:00")))
        XCTAssertEqual(historical.amountCents, 1800); XCTAssertTrue(restored.payments.isEmpty)
    }
}
