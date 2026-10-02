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
    func testPartnerAndFriendsCalendarsAreDistinctAndAuthoritative() {
        XCTAssertEqual(EventKind.classify(title: "compleanno casa", calendar: "Amici"), .friends)
        XCTAssertEqual(EventKind.classify(title: "pranzo", calendar: "DES <3"), .partner)
        XCTAssertEqual(EventKind.classify(title: "cinema con Des", calendar: "Amici"), .friends)
        XCTAssertEqual(EventKind.classify(title: "serata", calendar: "Desirée"), .partner)
        XCTAssertEqual(EventKind.classify(title: "destinazione", calendar: "Casa"), .other)
    }
    func testLegacySocialBackupKeepsRecordsWithoutNewCheckInField() throws {
        var data = AppData()
        var friend = event("friend", start: "2026-10-02T18:00:00+02:00", end: "2026-10-02T20:00:00+02:00", kind: .social)
        friend.calendarTitle = "Amici"
        var record = EventRecord(id: friend.id, snapshot: friend); record.notes = "Una bella serata"; record.status = .completed
        data.records[friend.id] = record
        data.checkIns["2026-10-02"] = DayCheckIn(id: "2026-10-02")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: BackupCodec.encode(data)) as? [String: Any])
        var checks = try XCTUnwrap(object["checkIns"] as? [String: [String: Any]])
        checks["2026-10-02"]?.removeValue(forKey: "universityAttendance")
        object["checkIns"] = checks
        let restored = try BackupCodec.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored.records[friend.id]?.snapshot.kind, .friends)
        XCTAssertEqual(restored.records[friend.id]?.notes, "Una bella serata")
        XCTAssertEqual(restored.records[friend.id]?.status, .completed)
        XCTAssertNil(restored.checkIns["2026-10-02"]?.universityAttendance)
        XCTAssertEqual(restored.installationID, data.installationID)
    }
    func testUniversityDecisionAffectsOnlyLecturesOnSelectedDay() {
        let lecture = event("lecture", start: "2026-10-02T08:30:00+02:00", end: "2026-10-02T10:30:00+02:00", kind: .university)
        let exam = event("exam", start: "2026-10-02T08:30:00+02:00", end: "2026-10-02T10:30:00+02:00", kind: .exam)
        let tomorrow = event("tomorrow", start: "2026-10-03T08:30:00+02:00", end: "2026-10-03T10:30:00+02:00", kind: .university)
        let study = event("study", start: "2026-10-02T15:00:00+02:00", end: "2026-10-02T17:00:00+02:00")
        var data = AppData(); var check = DayCheckIn(id: "2026-10-02"); check.universityAttendance = false; data.checkIns[check.id] = check
        XCTAssertEqual(Set(Planner.plannedEvents([lecture, exam, tomorrow, study], data: data).map(\.id)), Set(["exam", "tomorrow", "study"]))
        XCTAssertTrue(Report.day(lecture.start, events: [lecture], data: data).contains("Eventi da compilare: 0"))
        XCTAssertTrue(Report.day(lecture.start, events: [lecture], data: data).contains("non previste oggi"))
    }
    func testExplicitCalendarDecisionCanBeOverriddenLocally() {
        let lecture = event("lecture", start: "2026-10-02T08:30:00+02:00", end: "2026-10-02T10:30:00+02:00", kind: .university)
        var wake = event("wake", start: "2026-10-02T09:00:00+02:00", end: "2026-10-02T09:30:00+02:00", kind: .routine)
        wake.notes = "Routine\n\n" + Planner.universityOffNote + "\nGiornata di prova."
        XCTAssertEqual(Planner.plannedEvents([lecture, wake], data: AppData()).map(\.id), ["wake"])
        wake.notes = "Routine. " + Planner.universityOffNote + " Giornata di prova."
        XCTAssertEqual(Planner.plannedEvents([lecture, wake], data: AppData()).map(\.id), ["wake"])
        var data = AppData(); var check = DayCheckIn(id: "2026-10-02"); check.universityAttendance = true; data.checkIns[check.id] = check
        XCTAssertEqual(Planner.plannedEvents([lecture, wake], data: data).count, 2)
    }
    func testContradictionIsFlaggedWithoutSilentlyDroppingLecture() {
        let lecture = event("lecture", start: "2026-10-02T08:30:00+02:00", end: "2026-10-02T10:30:00+02:00", kind: .university)
        let wake = event("wake", start: "2026-10-02T09:00:00+02:00", end: "2026-10-02T09:30:00+02:00", kind: .routine)
        XCTAssertEqual(Planner.overlaps(on: wake.start, events: [lecture, wake], data: AppData()).count, 1)
        XCTAssertEqual(Planner.plannedEvents([lecture, wake], data: AppData()).count, 2)
        let adjacent = event("adjacent", start: "2026-10-02T10:30:00+02:00", end: "2026-10-02T11:30:00+02:00")
        XCTAssertTrue(Planner.overlaps(on: lecture.start, events: [lecture, adjacent], data: AppData()).isEmpty)
    }
    func testMultiDayEventCoversSecondDayAndHonorsExclusiveEnd() {
        var birthday = event("birthday", start: "2026-10-02T00:00:00+02:00", end: "2026-10-04T00:00:00+02:00", kind: .friends)
        birthday.isAllDay = true
        XCTAssertTrue(birthday.occurs(on: date("2026-10-03T15:00:00+02:00")))
        XCTAssertFalse(birthday.occurs(on: birthday.end))
        XCTAssertTrue(birthday.timeSummary.contains("tutto il giorno"))
        XCTAssertFalse(birthday.timeSummary.contains("2880"))
        XCTAssertFalse(birthday.timeSummary.contains("4 ott"))
    }
}
