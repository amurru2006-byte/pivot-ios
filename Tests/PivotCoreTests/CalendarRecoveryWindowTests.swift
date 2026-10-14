import XCTest
@testable import PivotCore

final class CalendarRecoveryWindowTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-14T12:00:00+02:00")!
    private func event(_ id: String, start: Double, duration: Double = 3600, location: String = "") -> CalendarItem {
        .init(id: id, eventIdentifier: id, calendarIdentifier: "test", calendarTitle: "Test", title: id,
              start: now.addingTimeInterval(start), end: now.addingTimeInterval(start + duration), location: location,
              notes: "", colorHex: "#000000", isAllDay: false, writable: true, kind: .workout)
    }
    private func state(_ target: CalendarItem) -> AppData {
        var data = AppData()
        data.rules[target.id] = .init(flexibility: .movable, minimumMinutes: 60, travelBeforeMinutes: 20, travelAfterMinutes: 20, travelConfirmed: true)
        return data
    }
    private func find(_ target: CalendarItem, _ events: [CalendarItem], _ data: AppData, now: Date? = nil) -> [CalendarRecoveryWindow] {
        let budget = CalendarTimeBudget.confirmed(activityMinutes: 75, rule: data.rules[target.id]!, preparationMinutes: 10)!
        return CalendarRecoveryWindows.find(target: target, budget: budget, events: events, data: data, now: now ?? self.now, days: 1)
    }
    func testSeventyFiveMinuteWorkoutNeedsOneHundredTwentyFiveMinuteWindow() throws {
        let gym = event("gym", start: -7200), data = state(gym)
        let window = try XCTUnwrap(find(gym, [gym], data).first)
        XCTAssertEqual(window.occupiedStart, now); XCTAssertEqual(window.activityStart, now.addingTimeInterval(1800))
        XCTAssertEqual(window.activityEnd, now.addingTimeInterval(6300)); XCTAssertEqual(window.occupiedEnd, now.addingTimeInterval(7500))
    }
    func testAFreeNinetyMinuteGapCannotContainWorkoutPlusTravel() throws {
        let gym = event("gym", start: -7200), fixed = event("lesson", start: 5400, duration: 3600), data = state(gym)
        let window = try XCTUnwrap(find(gym, [gym, fixed], data).first)
        XCTAssertEqual(window.occupiedStart, fixed.end)
    }
    func testOtherAppointmentsTravelBlocksBothSides() throws {
        let gym = event("gym", start: -7200), other = event("lesson", start: 8000), rule = state(gym).rules[gym.id]!
        var data = state(gym)
        data.rules[other.id] = .init(flexibility: .fixed, minimumMinutes: 60, travelBeforeMinutes: 20, travelAfterMinutes: 25, travelConfirmed: true)
        let budget = CalendarTimeBudget.confirmed(activityMinutes: 75, rule: rule, preparationMinutes: 10)!
        let result = CalendarRecoveryWindows.find(target: gym, budget: budget, events: [gym, other], data: data, now: now, days: 1)
        XCTAssertEqual(result.first?.occupiedStart, other.end.addingTimeInterval(1500))
    }
    func testUnknownTravelAndAllDayAvailabilityDoNotBecomeFreeTime() {
        let gym = event("gym", start: -7200), unknown = event("lesson", start: 20000, location: "Altro luogo"), data = state(gym)
        XCTAssertTrue(find(gym, [gym, unknown], data).isEmpty)
        var allDay = event("busy", start: -12 * 3600, duration: 86400); allDay.isAllDay = true
        XCTAssertTrue(find(gym, [gym, allDay], data).isEmpty)
    }
    func testStaleDeletedReadOnlyFixedAndStartedTargetsAreRejected() {
        let gym = event("gym", start: -7200), data = state(gym)
        XCTAssertTrue(find(gym, [], data).isEmpty)
        var changed = gym; changed.title = "Changed"
        XCTAssertTrue(find(gym, [changed], data).isEmpty)
        var readOnly = gym; readOnly.writable = false
        XCTAssertTrue(find(readOnly, [readOnly], state(readOnly)).isEmpty)
        var fixed = data; fixed.rules[gym.id]?.flexibility = .fixed
        XCTAssertTrue(find(gym, [gym], fixed).isEmpty)
        for status in [Completion.running, .completed, .partial] {
            var recorded = data; recorded.records[gym.id] = .init(id: gym.id, snapshot: gym, status: status)
            XCTAssertTrue(find(gym, [gym], recorded).isEmpty)
        }
    }
    func testExistingPendingProposalAndQuietHoursAreRespected() {
        let gym = event("gym", start: -7200)
        var data = state(gym)
        data.moves = [.init(source: gym, proposedStart: now.addingTimeInterval(3600), proposedEnd: now.addingTimeInterval(7200))]
        XCTAssertTrue(find(gym, [gym], data).isEmpty)
        data.moves = []
        XCTAssertTrue(find(gym, [gym], data, now: now.addingTimeInterval(9 * 3600)).isEmpty)
    }
    func testAnotherPreparationBudgetAndOverlappingBlocksAreMergedByCursor() throws {
        let gym = event("gym", start: -7200), other = event("lesson", start: 8000), overlap = event("overlap", start: 9000, duration: 7200)
        var data = state(gym)
        data.rules[other.id] = .init(flexibility: .fixed, minimumMinutes: 60, travelBeforeMinutes: 20, travelAfterMinutes: 25, travelConfirmed: true)
        let own = CalendarTimeBudget.confirmed(activityMinutes: 75, rule: data.rules[gym.id]!, preparationMinutes: 10)!
        let another = CalendarTimeBudget.confirmed(activityMinutes: 60, rule: data.rules[other.id]!, preparationMinutes: 30)!
        let result = CalendarRecoveryWindows.find(target: gym, budget: own, events: [gym, other, overlap], data: data, otherBudgets: [other.id: another], now: now, days: 1)
        XCTAssertEqual(result.first?.occupiedStart, overlap.end)
    }
    func testReviewAndWindowSearchDoNotMutateCalendarOrData() throws {
        let gym = event("gym", start: -7200), events = [gym], data = state(gym), bytes = try BackupCodec.encode(data)
        XCTAssertFalse(find(gym, events, data).isEmpty)
        XCTAssertEqual(events[0].start, gym.start); XCTAssertEqual(bytes, try BackupCodec.encode(data))
    }
}
