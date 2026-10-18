import XCTest
@testable import PivotCore

final class DayPlanningContextTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-18T12:00:00+02:00")!
    private func event(_ id: String, hour: Int, minutes: Int, location: String = "") -> CalendarItem {
        let start = PivotDate.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now)!
        return .init(id: id, eventIdentifier: id, calendarIdentifier: "qa", calendarTitle: "Calendario QA", title: "Attività QA",
                     start: start, end: start.addingTimeInterval(Double(minutes) * 60), location: location, notes: "", colorHex: "7EE6CD",
                     isAllDay: false, writable: true, kind: .other)
    }
    func testMissingSleepAndRatingsStayUnknownNotZeroOrAReadinessScore() throws {
        let value = try XCTUnwrap(DayPlanningContext.make(events: [], data: AppData(), now: now))
        XCTAssertNil(value.sleepMinutes); XCTAssertNil(value.sleepSource); XCTAssertNil(value.reportedEnergy)
        XCTAssertNil(value.reportedFatigue); XCTAssertEqual(value.freeMinutes, 600)
    }
    func testOverlappingAppointmentsAndDuplicateEventsDoNotInflateLoad() throws {
        let first = event("a", hour: 13, minutes: 120), second = event("b", hour: 14, minutes: 120)
        let result = try XCTUnwrap(DayPlanningContext.make(events: [first, first, second], data: AppData(), now: now))
        XCTAssertEqual(result.scheduledMinutes, 180); XCTAssertEqual(result.freeMinutes, 420)
    }
    func testUnconfirmedLocatedAppointmentIsNotAZeroTravelClaim() {
        let value = DayPlanningContext.make(events: [event("a", hour: 13, minutes: 60, location: "Luogo QA")], data: AppData(), now: now)
        XCTAssertEqual(value?.unknownTravelCount, 1); XCTAssertEqual(value?.scheduledMinutes, 60)
    }
    func testHealthRevocationHidesImportedSleepButNotManualSleep() {
        var data = AppData()
        data.checkIns[PivotDate.key(now)] = .init(id: PivotDate.key(now), energyMorning: 4,
                                                 sleep: .init(durationSeconds: 7 * 3600, importedFromHealth: true))
        XCTAssertNil(DayPlanningContext.make(events: [], data: data, now: now)?.sleepMinutes)
        data.settings.healthEnabled = true
        XCTAssertEqual(DayPlanningContext.make(events: [], data: data, now: now)?.sleepMinutes, 420)
        XCTAssertEqual(DayPlanningContext.make(events: [], data: data, now: now)?.reportedEnergy, 4)
        data.settings.healthEnabled = false; data.checkIns[PivotDate.key(now)]?.sleep?.importedFromHealth = false
        XCTAssertEqual(DayPlanningContext.make(events: [], data: data, now: now)?.sleepSource, .manual)
    }
    func testPastAppointmentIsNotAutomaticallyCompletedFromSleepOrMissingData() {
        let value = DayPlanningContext.make(events: [event("a", hour: 9, minutes: 60)], data: AppData(), now: now)
        XCTAssertEqual(value?.missedUnconfirmedCount, 1)
    }
    func testAllDayBusyAndOutsideWakingWindowAreNotFreeTime() {
        var item = event("all", hour: 0, minutes: 1440); item.isAllDay = true
        XCTAssertEqual(DayPlanningContext.make(events: [item], data: AppData(), now: now)?.freeMinutes, 0)
        XCTAssertEqual(DayPlanningContext.make(events: [], data: AppData(), now: now.addingTimeInterval(11 * 3600))?.freeMinutes, 0)
    }
}
