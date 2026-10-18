import XCTest
@testable import PivotCore

final class RecoveryForecastTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-18T12:00:00+02:00")!
    private var target: CalendarItem {
        .init(id: "target", eventIdentifier: "target", calendarIdentifier: "qa", calendarTitle: "QA", title: "Attività sintetica",
              start: now.addingTimeInterval(-3 * 3600), end: now.addingTimeInterval(-2 * 3600),
              location: "", notes: "", colorHex: "7EE6CD", isAllDay: false, writable: true, kind: .workout)
    }
    private var data: AppData {
        var data = AppData(); data.rules[target.id] = .init(flexibility: .movable, minimumMinutes: 60, travelConfirmed: true)
        return data
    }
    func testConfirmedPreferencesExpireAndStayLocalInTheOnlineDTO() throws {
        var data = data
        let value = RecoveryPlanningPreferences(horizonDays: 7, preferredBand: .evening, confirmedAt: now, expiresAt: now.addingTimeInterval(60))
        XCTAssertTrue(value.isActive(at: now)); XCTAssertFalse(value.isActive(at: now.addingTimeInterval(60)))
        data.settings.recoveryPlanningPreferences = value
        let request = try CoachV8Snapshot.make(message: "Organizza la giornata", events: [], data: data, now: now, purpose: "conversation")
        XCTAssertFalse(String(decoding: request.encodedRequest, as: UTF8.self).contains("recoveryPlanningPreferences"))
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(data)).settings.recoveryPlanningPreferences, value)
    }
    func testMalformedPreferencesAreRejectedByBackupWithoutReplacingThem() throws {
        var data = data
        data.settings.recoveryPlanningPreferences = .init(horizonDays: 8, confirmedAt: now)
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(data)))
        data.settings.recoveryPlanningPreferences = .init(confirmedAt: now, expiresAt: now)
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(data)))
    }
    func testFullDurationAndExplicitEveningPreferenceAreHonoredWithoutCalendarWrites() {
        let options = RecoveryForecast.options(targetID: target.id, events: [target], data: data, now: now, preferredBand: .evening)
        XCTAssertFalse(options.isEmpty)
        for option in options {
            XCTAssertNil(CoachPlanner.validate(option, events: [target], data: data, now: now))
            XCTAssertEqual(option.moves[0].proposedEnd.timeIntervalSince(option.moves[0].proposedStart), 3600)
            XCTAssertGreaterThanOrEqual(PivotDate.calendar.component(.hour, from: option.moves[0].proposedStart), 18)
        }
        XCTAssertTrue(data.moves.isEmpty); XCTAssertTrue(data.coachState.pendingCalendarChanges.isEmpty)
    }
    func testCanSearchBeyondThreeDaysAndDoesNotImposeRestDays() {
        let day = PivotDate.calendar.startOfDay(for: now)
        var busy = target; busy.id = "busy"; busy.eventIdentifier = "busy"; busy.isAllDay = true
        busy.start = day; busy.end = PivotDate.calendar.date(byAdding: .day, value: 4, to: day)!
        XCTAssertTrue(RecoveryForecast.options(targetID: target.id, events: [target, busy], data: data, now: now, days: 3).isEmpty)
        let values = RecoveryForecast.options(targetID: target.id, events: [target, busy], data: data, now: now, days: 7)
        XCTAssertFalse(values.isEmpty)
        XCTAssertGreaterThanOrEqual(values[0].moves[0].proposedStart, busy.end)
    }
    func testUnknownTargetOrOtherTravelDoesNotProduceUnsafeOptions() {
        var data = data; data.rules[target.id]?.travelConfirmed = false
        XCTAssertTrue(RecoveryForecast.options(targetID: target.id, events: [target], data: data, now: now).isEmpty)
        data.rules[target.id]?.travelConfirmed = true
        var busy = target; busy.id = "unknown"; busy.eventIdentifier = "unknown"; busy.location = "Luogo QA"
        busy.start = now.addingTimeInterval(3600); busy.end = busy.start.addingTimeInterval(3600)
        XCTAssertTrue(RecoveryForecast.options(targetID: target.id, events: [target, busy], data: data, now: now, days: 1).isEmpty)
    }
    func testFreshValidationRejectsDeletedMovedAndAllDayConflicts() throws {
        let option = try XCTUnwrap(RecoveryForecast.options(targetID: target.id, events: [target], data: data, now: now).first)
        XCTAssertNotNil(CoachPlanner.validate(option, events: [], data: data, now: now))
        var changed = target; changed.location = "Nuovo luogo QA"
        XCTAssertNotNil(CoachPlanner.validate(option, events: [changed], data: data, now: now))
        var allDay = target; allDay.id = "all-day"; allDay.isAllDay = true
        allDay.start = PivotDate.calendar.startOfDay(for: option.moves[0].proposedStart); allDay.end = allDay.start.addingTimeInterval(86400)
        XCTAssertNotNil(CoachPlanner.validate(option, events: [target, allDay], data: data, now: now))
    }
    func testReadOnlyCompletedRunningFutureAndAlreadyStagedActivitiesAreExcluded() {
        var data = data
        for status in [Completion.completed, .partial, .running] {
            data.records[target.id] = .init(id: target.id, snapshot: target, status: status)
            XCTAssertTrue(RecoveryForecast.options(targetID: target.id, events: [target], data: data, now: now).isEmpty)
        }
        data.records = [:]
        var future = target; future.start = now.addingTimeInterval(3600); future.end = future.start.addingTimeInterval(3600)
        XCTAssertTrue(RecoveryForecast.options(targetID: target.id, events: [future], data: data, now: now).isEmpty)
        data.moves = [.init(source: target, proposedStart: now.addingTimeInterval(3600), proposedEnd: now.addingTimeInterval(7200))]
        XCTAssertTrue(RecoveryForecast.options(targetID: target.id, events: [target], data: data, now: now).isEmpty)
    }
}
