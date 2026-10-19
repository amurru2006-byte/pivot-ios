import XCTest
@testable import PivotCore

final class CoachRecoveryRequestTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-19T12:00:00+02:00")!
    private func event(_ id: String, title: String = "Squat QA") -> CalendarItem {
        .init(id: id, eventIdentifier: id, calendarIdentifier: "qa", calendarTitle: "QA", title: title,
              start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600), location: "", notes: "",
              colorHex: "7EE6CD", isAllDay: false, writable: true, kind: .workout)
    }
    func testExplicitRecoveryCarriesDayBandAndOriginalMessageWithoutSendingItOnline() throws {
        let text = "Vorrei recuperare la palestra domani sera"
        let request = try XCTUnwrap(CoachRecoveryRequest.parse(text, now: now))
        XCTAssertEqual(request.dayOffset, 1); XCTAssertEqual(request.band, .evening); XCTAssertTrue(request.workoutOnly)
        XCTAssertEqual(request.instruction, text)
        var data = AppData()
        data.coachState.messages = [.init(dayKey: PivotDate.key(now), role: .coach, text: "Apri recupero", recoveryRequest: request)]
        let snapshot = try CoachV8Snapshot.make(message: "Ciao", events: [], data: data, now: now, purpose: "conversation", protocolVersion: 3)
        XCTAssertFalse(String(decoding: snapshot.encodedRequest, as: UTF8.self).contains(text))
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(data)).coachState.messages[0].recoveryRequest, request)
    }
    func testTodayAndAfterTomorrowAreNotConfusedWithTomorrow() throws {
        XCTAssertEqual(try XCTUnwrap(CoachRecoveryRequest.parse("Recupera palestra oggi", now: now)).dayOffset, 0)
        XCTAssertEqual(try XCTUnwrap(CoachRecoveryRequest.parse("Recupera palestra dopo domani", now: now)).dayOffset, 2)
        XCTAssertEqual(try XCTUnwrap(CoachRecoveryRequest.parse("Recupera palestra dopodomani", now: now)).dayOffset, 2)
        XCTAssertEqual(try XCTUnwrap(CoachRecoveryRequest.parse("Recupera palestra stasera", now: now)).band, .evening)
    }
    func testNegationsConditionsMedicalRequestsAndUnsupportedDatesStayInConversation() {
        for text in ["Non recuperare palestra", "Recupera palestra se sto bene", "Recupera palestra ma ho dolore", "Recupera palestra con febbre",
                     "Elimina e recupera palestra", "Crea recupero palestra", "Recupera palestra alle 19:30", "Recupera palestra il 25", "Recupera palestra lunedì",
                     "Recupera palestra oggi e domani", "Recupera palestra mattina o sera", "Recupera palestra la prossima settimana"] {
            XCTAssertNil(CoachRecoveryRequest.parse(text, now: now), text)
        }
    }
    func testAUniqueNamedTargetIsResolvedButTwoEquivalentSessionsRequireChoice() throws {
        let values = [event("one", title: "Squat QA"), event("two", title: "Bench QA")]
        let request = try XCTUnwrap(CoachRecoveryRequest.parse("Recupera Squat QA domani", now: now))
        XCTAssertEqual(request.resolving(text: "Recupera Squat QA domani", events: values, data: AppData(), now: now).targetID, "one")
        XCTAssertNil(request.resolving(text: "Recupera palestra domani", events: values, data: AppData(), now: now).targetID)
    }
    func testReadOnlyFutureCompletedAndAlreadyMovedEventsAreNotOffered() {
        let target = event("target"); var data = AppData()
        XCTAssertEqual(CoachRecoveryRequest.candidates(events: [target], data: data, now: now).count, 1)
        data.records[target.id] = .init(id: target.id, snapshot: target, status: .completed)
        XCTAssertTrue(CoachRecoveryRequest.candidates(events: [target], data: data, now: now).isEmpty)
        data.records = [:]; data.moves = [.init(source: target, proposedStart: now.addingTimeInterval(3600), proposedEnd: now.addingTimeInterval(7200))]
        XCTAssertTrue(CoachRecoveryRequest.candidates(events: [target], data: data, now: now).isEmpty)
        var future = target; future.start = now.addingTimeInterval(3600); future.end = now.addingTimeInterval(7200)
        var readOnly = target; readOnly.writable = false
        XCTAssertTrue(CoachRecoveryRequest.candidates(events: [future, readOnly], data: AppData(), now: now).isEmpty)
    }
    func testExactRequestedDayDoesNotFallBackToAnotherDayWhenBusy() throws {
        let target = event("target"); var data = AppData()
        data.rules[target.id] = .init(flexibility: .movable, minimumMinutes: 60, travelConfirmed: true)
        let tomorrow = PivotDate.calendar.date(byAdding: .day, value: 1, to: PivotDate.calendar.startOfDay(for: now))!
        let options = RecoveryForecast.options(targetID: target.id, events: [target], data: data, now: now, preparationIncluded: true, onDay: tomorrow)
        XCTAssertFalse(options.isEmpty)
        XCTAssertTrue(options.allSatisfy { PivotDate.calendar.isDate($0.moves[0].proposedStart, inSameDayAs: tomorrow) })
        var busy = event("busy"); busy.isAllDay = true; busy.start = tomorrow
        busy.end = PivotDate.calendar.date(byAdding: .day, value: 1, to: tomorrow)!
        XCTAssertTrue(RecoveryForecast.options(targetID: target.id, events: [target, busy], data: data, now: now, preparationIncluded: true, onDay: tomorrow).isEmpty)
        XCTAssertFalse(RecoveryForecast.options(targetID: target.id, events: [target, busy], data: data, now: now, preparationIncluded: true).isEmpty)
        XCTAssertTrue(data.moves.isEmpty); XCTAssertTrue(data.coachState.pendingCalendarChanges.isEmpty)
    }
    func testExpiredRequestedDayAndOutOfHorizonDoNotShiftSilently() {
        let target = event("target"); var data = AppData()
        data.rules[target.id] = .init(flexibility: .movable, minimumMinutes: 60, travelConfirmed: true)
        for offset in [-1, 7] {
            let day = PivotDate.calendar.date(byAdding: .day, value: offset, to: now)!
            XCTAssertTrue(RecoveryForecast.options(targetID: target.id, events: [target], data: data, now: now, preparationIncluded: true, onDay: day).isEmpty)
        }
    }
    func testRelativeDayUsesCalendarArithmeticAcrossEndOfDaylightSaving() throws {
        let before = ISO8601DateFormatter().date(from: "2026-10-24T23:00:00+02:00")!
        let request = try XCTUnwrap(CoachRecoveryRequest.parse("Recupera palestra dopo domani", now: before))
        XCTAssertEqual(request.day.map(PivotDate.key), "2026-10-26")
    }
    func testTodayNearMidnightCannotTurnIntoTomorrowAndUnknownActivityIsNotGuessed() throws {
        let target = event("target"); var data = AppData()
        data.rules[target.id] = .init(flexibility: .movable, minimumMinutes: 60, travelConfirmed: true)
        let late = ISO8601DateFormatter().date(from: "2026-10-19T23:58:00+02:00")!
        XCTAssertTrue(RecoveryForecast.options(targetID: target.id, events: [target], data: data, now: late, preparationIncluded: true, onDay: late).isEmpty)
        let request = try XCTUnwrap(CoachRecoveryRequest.parse("Recupera matematica domani", now: now))
        XCTAssertNil(request.resolving(text: "Recupera matematica domani", events: [target], data: data, now: now).targetID)
    }
}
