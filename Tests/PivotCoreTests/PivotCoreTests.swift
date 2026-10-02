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
    func testWorkCalendarDoesNotBecomeUniversityOrPersonalStudy() {
        XCTAssertEqual(EventKind.classify(title: "laboratorio chimica con uno studente", calendar: "Lavoro"), .tutoring)
        XCTAssertEqual(EventKind.classify(title: "studio matematica", calendar: "Lavoro"), .tutoring)
        XCTAssertEqual(EventKind.classify(title: "preparazione esame", calendar: "Lavoro"), .tutoring)
        XCTAssertEqual(EventKind.classify(title: "Chimica generale", calendar: "Unimi-L27"), .university)
        XCTAssertEqual(EventKind.classify(title: "studio matematica", calendar: "Unimi-L27"), .study)
    }
    func testImportedLessonAppearsOnceWithItsExistingAnswer() {
        var cloud = event("cloud", start: "2026-10-03T11:00:00+02:00", end: "2026-10-03T12:00:00+02:00", kind: .tutoring)
        cloud.title = "lezione studente "; cloud.calendarTitle = "Lavoro"; cloud.calendarIdentifier = "icloud-work"; cloud.sourceIdentifier = "icloud"; cloud.sourceTitle = "iCloud"
        var google = cloud; google.id = "google"; google.eventIdentifier = "google"; google.calendarIdentifier = "google-work"; google.sourceIdentifier = "google"; google.sourceTitle = "Google"; google.notes = "Indicazioni aggiornate"
        var data = AppData(); var record = EventRecord(id: cloud.id, snapshot: cloud); record.status = .completed; record.activeMinutes = 60; record.tutoringAnswered = true; record.notes = "Argomenti affrontati"; data.records[cloud.id] = record
        let items = Planner.plannedEvents([cloud, google], data: data)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, cloud.id)
        XCTAssertEqual(items[0].notes, google.notes)
        XCTAssertEqual(items[0].calendarIdentifier, google.calendarIdentifier)
        XCTAssertEqual(data.records[items[0].id]?.activeMinutes, 60)
        XCTAssertEqual(data.records[items[0].id]?.notes, "Argomenti affrontati")
        XCTAssertEqual(Planner.plannedEvents(items, data: data), items)
        XCTAssertTrue(Planner.overlaps(on: cloud.start, events: [cloud, google], data: data).isEmpty)
        XCTAssertTrue(Report.day(cloud.start, events: [cloud, google], data: data).contains("Eventi da compilare: 0"))
    }
    func testTimedBirthdayWinsOverItsStaleAllDayImport() {
        var allDay = event("all-day", start: "2026-10-03T00:00:00+02:00", end: "2026-10-05T00:00:00+02:00", kind: .friends)
        allDay.isAllDay = true; allDay.title = "compleanno"; allDay.calendarTitle = "Amici"; allDay.calendarIdentifier = "icloud-friends"; allDay.sourceIdentifier = "icloud"
        var timed = allDay; timed.id = "timed"; timed.eventIdentifier = "timed"; timed.calendarIdentifier = "google-friends"; timed.sourceIdentifier = "google"; timed.sourceTitle = "Google"; timed.isAllDay = false; timed.start = date("2026-10-03T15:00:00+02:00"); timed.end = date("2026-10-04T10:00:00+02:00")
        let items = Planner.plannedEvents([allDay, timed], data: AppData())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].start, timed.start)
        XCTAssertEqual(items[0].end, timed.end)
        XCTAssertFalse(items[0].isAllDay)
        XCTAssertEqual(items[0].agendaStart(on: timed.start), "15:00")
        XCTAssertEqual(items[0].agendaStart(on: timed.end), "In corso")
        XCTAssertEqual(items[0].agendaEnd(on: timed.end), "10:00")
        XCTAssertTrue(items[0].occurs(on: timed.end))
        XCTAssertFalse(items[0].occurs(on: date("2026-10-05T00:00:00+02:00")))
    }
    func testMatchingNamesDoNotEraseDifferentAppointments() {
        var a = event("a", start: "2026-10-03T11:00:00+02:00", end: "2026-10-03T12:00:00+02:00", kind: .tutoring)
        a.calendarTitle = "Lavoro"; a.calendarIdentifier = "work-a"; a.sourceIdentifier = "google"
        var b = a; b.id = "b"; b.eventIdentifier = "b"; b.externalIdentifier = "b"; b.calendarIdentifier = "work-b"
        XCTAssertEqual(EventCoalescer.unique([a, b], data: AppData()).count, 2)
        var snapshot = a; snapshot.sourceIdentifier = nil
        var data = AppData(); data.records[a.id] = EventRecord(id: a.id, snapshot: snapshot)
        XCTAssertEqual(Set(EventCoalescer.unique([a, b], data: data).map(\.id)), Set(["a", "b"]))
        b.sourceIdentifier = "icloud"; b.location = "Altro luogo"; a.location = "Luogo uno"
        XCTAssertEqual(EventCoalescer.unique([a, b], data: AppData()).count, 2)
        b.location = a.location; b.start = date("2026-10-10T11:00:00+02:00"); b.end = date("2026-10-10T12:00:00+02:00"); b.externalIdentifier = a.externalIdentifier
        XCTAssertEqual(EventCoalescer.unique([a, b], data: AppData()).count, 2)
    }
    func testSameEventReturnedTwiceIsCollapsed() {
        let item = event("same", start: "2026-10-03T11:00:00+02:00", end: "2026-10-03T12:00:00+02:00")
        XCTAssertEqual(EventCoalescer.unique([item, item], data: AppData()), [item])
    }
    func testRecoveryMoveSurvivesImportedDuplicate() {
        var a = event("a", start: "2026-10-03T11:00:00+02:00", end: "2026-10-03T12:00:00+02:00")
        a.calendarTitle = "Unimi-L27"; a.calendarIdentifier = "icloud-uni"; a.sourceIdentifier = "icloud"
        var b = a; b.id = "b"; b.eventIdentifier = "b"; b.calendarIdentifier = "google-uni"; b.sourceIdentifier = "google"; b.sourceTitle = "Google"
        var data = AppData(); let start = date("2026-10-03T17:00:00+02:00"); let end = date("2026-10-03T18:00:00+02:00")
        data.moves = [.init(source: a, proposedStart: start, proposedEnd: end)]
        let items = Planner.plannedEvents([a, b], data: data)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, a.id)
        XCTAssertEqual(items[0].start, start)
        XCTAssertEqual(items[0].end, end)
    }
    func testOlderWorkSnapshotMigratesWithoutChangingMoneyOrAnswers() throws {
        var old = event("old", start: "2026-10-03T11:00:00+02:00", end: "2026-10-03T12:00:00+02:00", kind: .university)
        old.title = "laboratorio chimica"; old.calendarTitle = "Lavoro"
        var data = AppData(); var record = EventRecord(id: old.id, snapshot: old); record.notes = "Risposte salvate"; data.records[old.id] = record
        let restored = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertEqual(restored.records[old.id]?.snapshot.kind, .tutoring)
        XCTAssertEqual(restored.records[old.id]?.notes, record.notes)
        XCTAssertEqual(restored.income.count, data.income.count)
    }
    func testAnnualOpeningAndNewYearNeverEraseHistoricalMoney() throws {
        var ledger = AnnualLedger()
        let lessonID = UUID()
        let old = Payment(incomeID: lessonID, clientName: "Test", date: date("2026-12-31T23:59:00+01:00"), amountCents: 1800)
        let new = Payment(incomeID: lessonID, clientName: "Test", date: date("2027-01-01T00:01:00+01:00"), amountCents: 1200)
        ledger.setOpeningTotal(23000, year: 2026, payments: [old])
        XCTAssertEqual(ledger.total(year: 2026, payments: [old, new]), 23000)
        XCTAssertEqual(ledger.total(year: 2027, payments: [old, new]), 1200)
        ledger.setOpeningTotal(23000, year: 2026, payments: [old])
        XCTAssertEqual(ledger.total(year: 2026, payments: [old]), 23000)
        XCTAssertEqual(ledger.total(year: 2028, payments: [old, new]), 0)
    }
    func testIncomeWarningBoundariesAndProgress() {
        let ledger = AnnualLedger()
        XCTAssertNil(ledger.warningProgress(total: 449999))
        XCTAssertEqual(ledger.warningProgress(total: 450000), 0)
        XCTAssertEqual(ledger.warningProgress(total: 475000), 0.5)
        XCTAssertEqual(ledger.warningProgress(total: 500000), 1)
        XCTAssertEqual(ledger.warningProgress(total: 530000), 1)
        XCTAssertEqual(ledger.band(total: 450000), "approaching")
        XCTAssertEqual(ledger.band(total: 500000), "reference")
    }
    func testTutoringPaymentSavedOnceAndOnlyCashCounts() throws {
        let item = event("tutor", start: "2026-10-03T11:00:00+02:00", end: "2026-10-03T12:00:00+02:00", kind: .tutoring)
        var data = AppData(); data.ledger = AnnualLedger()
        let client = Client(name: "Test", rateCents: 1800)
        var record = EventRecord(id: item.id, snapshot: item); record.status = .completed
        let first = TutoringLedger.register(event: item, record: &record, client: client, amountCents: 1800, collectedCents: 800, paymentDate: item.end, data: &data)
        data.records[item.id] = record
        let second = TutoringLedger.register(event: item, record: &record, client: client, amountCents: 1800, collectedCents: 1800, paymentDate: item.end, data: &data)
        XCTAssertEqual(first, second); XCTAssertEqual(data.income.count, 1); XCTAssertEqual(data.payments.count, 1)
        XCTAssertEqual(data.income[0].outstandingCents, 1000)
        XCTAssertEqual(data.ledger?.total(year: 2026, payments: data.payments), 800)
        let restored = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertEqual(restored.records[item.id]?.incomeID, first)
        XCTAssertEqual(restored.income[0].calendarEventID, item.id)
    }
    func testTutoringZeroAndUnpaidDoNotCreditAccount() {
        let item = event("tutor", start: "2026-10-03T11:00:00+02:00", end: "2026-10-03T12:00:00+02:00", kind: .tutoring)
        var data = AppData(); let client = Client(name: "Test", rateCents: 1800)
        var record = EventRecord(id: item.id, snapshot: item)
        TutoringLedger.register(event: item, record: &record, client: client, amountCents: 0, collectedCents: 0, paymentDate: item.end, data: &data)
        XCTAssertTrue(data.income.isEmpty); XCTAssertEqual(record.tutoringAnswered, true)
        XCTAssertNil(TutoringLedger.register(event: item, record: &record, client: client, amountCents: 1000, collectedCents: 1200, paymentDate: item.end, data: &data))
        XCTAssertTrue(data.payments.isEmpty)
        TutoringLedger.register(event: item, record: &record, client: client, amountCents: 1800, collectedCents: 0, paymentDate: item.end, data: &data)
        XCTAssertEqual(data.income[0].outstandingCents, 1800); XCTAssertTrue(data.payments.isEmpty)
    }
    func testLegacyBackupWithoutNewFieldsAndLedgerValidation() throws {
        let bytes = try BackupCodec.encode(AppData())
        let old = try BackupCodec.decode(bytes)
        XCTAssertNil(old.ledger)
        var data = old; data.ledger = AnnualLedger(); data.ledger?.openingCents["2026"] = -1
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(data)))
    }
    func testExactCalendarColorSurvivesImportedCopies() {
        var cloud = event("cloud", start: "2026-10-03T11:00:00+02:00", end: "2026-10-03T12:00:00+02:00")
        cloud.sourceIdentifier = "cloud"; cloud.sourceTitle = "iCloud"; cloud.colorHex = "#D02D68"
        var google = cloud; google.id = "google"; google.calendarIdentifier = "google"; google.sourceIdentifier = "google"; google.sourceTitle = "Google"; google.colorHex = "#791A3D"
        XCTAssertEqual(EventCoalescer.unique([cloud, google], data: AppData())[0].colorHex, "#D02D68")
    }
    func testCalendarTimeAndTitleChangesKeepAnswerAndAvoidStaleLocalMove() {
        let old = event("old", start: "2026-10-03T11:00:00+02:00", end: "2026-10-03T12:00:00+02:00")
        var current = old; current.id = "new"; current.title = "Titolo aggiornato"; current.start = date("2026-10-03T13:00:00+02:00"); current.end = date("2026-10-03T14:00:00+02:00")
        var data = AppData(); var record = EventRecord(id: old.id, snapshot: old); record.notes = "Salvato"; data.records[old.id] = record
        data.moves.append(.init(source: old, proposedStart: date("2026-10-03T17:00:00+02:00"), proposedEnd: date("2026-10-03T18:00:00+02:00")))
        let item = Planner.effectiveEvents([current], data: data)[0]
        XCTAssertEqual(item.id, old.id); XCTAssertEqual(item.title, current.title); XCTAssertEqual(item.start, current.start)
        XCTAssertEqual(data.records[item.id]?.notes, "Salvato")
    }
    func testExcelWorkbookUsesActualPaymentsAndLiteralUserText() throws {
        var data = AppData(); data.ledger = AnnualLedger()
        let client = Client(name: "=1+1 & <test>", rateCents: 1800)
        let entry = IncomeEntry(clientID: client.id, clientName: client.name, date: date("2025-12-31T11:00:00+01:00"), minutes: 60, amountCents: 1800, paidCents: 1800, notes: "=HYPERLINK(\"example\")")
        data.clients = [client]; data.income = [entry]
        data.payments = [.init(incomeID: entry.id, clientName: client.name, date: date("2026-01-02T11:00:00+01:00"), amountCents: 1800)]
        data.ledger?.openingCents["2026"] = 10000
        let bytes = LedgerExcel.make(data: data, year: 2026)
        XCTAssertEqual(Array(bytes.prefix(4)), [0x50,0x4b,0x03,0x04])
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertTrue(text.contains("=1+1 &amp; &lt;test&gt;")); XCTAssertFalse(text.contains("<f>"))
        XCTAssertTrue(text.contains("118.00")); XCTAssertTrue(text.contains("2025-12-31")); XCTAssertTrue(text.contains("2026-01-02"))
        if let path = ProcessInfo.processInfo.environment["PIVOT_TEST_EXPORT_PATH"] {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: url)
        }
    }

    func testCompletedTutoringStillAsksForItsMissingCompensation() {
        let item = event("tutor", start: "2026-10-03T11:00:00+02:00", end: "2026-10-03T12:00:00+02:00", kind: .tutoring)
        var data = AppData(); var record = EventRecord(id: item.id, snapshot: item); record.status = .completed
        data.records[item.id] = record
        XCTAssertTrue(Report.day(item.start, events: [item], data: data).contains("Manca il compenso"))
        record.tutoringAnswered = true; data.records[item.id] = record
        XCTAssertFalse(Report.day(item.start, events: [item], data: data).contains("Manca il compenso"))
    }

    func testExternalCalendarEditsPreferNewestCopyWithRenamedEvent() {
        var google = event("google", start: "2026-10-03T11:00:00+02:00", end: "2026-10-03T12:00:00+02:00")
        google.externalIdentifier = "shared"; google.sourceIdentifier = "google"; google.sourceTitle = "Google"; google.recurring = false; google.calendarModifiedAt = date("2026-10-02T10:00:00+02:00")
        var cloud = google; cloud.id = "cloud"; cloud.calendarIdentifier = "cloud"; cloud.sourceIdentifier = "cloud"; cloud.sourceTitle = "iCloud"; cloud.title = "Titolo nuovo"; cloud.start = date("2026-10-04T15:00:00+02:00"); cloud.end = date("2026-10-04T16:00:00+02:00"); cloud.notes = "Nuove indicazioni"; cloud.location = "Nuovo luogo"; cloud.calendarModifiedAt = date("2026-10-03T10:00:00+02:00")
        let items = EventCoalescer.unique([google, cloud], data: AppData())
        XCTAssertEqual(items.count, 1); XCTAssertEqual(items[0].title, cloud.title); XCTAssertEqual(items[0].start, cloud.start); XCTAssertEqual(items[0].notes, cloud.notes); XCTAssertEqual(items[0].location, cloud.location)
    }
    func testOneOffDateChangeKeepsAnswersAndRecurringInstancesStaySeparate() {
        var old = event("old", start: "2026-10-03T11:00:00+02:00", end: "2026-10-03T12:00:00+02:00")
        old.recurring = false
        var current = old; current.id = "new"; current.start = date("2026-10-05T15:00:00+02:00"); current.end = date("2026-10-05T16:00:00+02:00")
        var data = AppData(); var record = EventRecord(id: old.id, snapshot: old); record.notes = "Risposta"; data.records[old.id] = record
        XCTAssertEqual(EventCoalescer.unique([current], data: data)[0].id, old.id)
        XCTAssertTrue(Planner.plannedEvents([], data: data).isEmpty)
        old.recurring = true; old.occurrenceAnchor = old.start; current.recurring = true; current.occurrenceAnchor = current.start
        XCTAssertFalse(EventCoalescer.savedOccurrence(old, current))
    }

}
