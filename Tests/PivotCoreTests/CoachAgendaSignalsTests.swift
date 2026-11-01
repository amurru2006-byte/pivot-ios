import XCTest
@testable import PivotCore

final class CoachAgendaSignalsTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-19T10:00:00+02:00")!
    private func event(_ id: String, start: Double = 3600, end: Double = 7200) -> CalendarItem {
        .init(id: id, eventIdentifier: "native-" + id, calendarIdentifier: "qa", calendarTitle: "QA",
              title: "Impegno sintetico " + id, start: now.addingTimeInterval(start), end: now.addingTimeInterval(end),
              location: "", notes: "", colorHex: "7EE6CD", isAllDay: false, writable: true, kind: .workout)
    }
    private func data(_ events: [CalendarItem]) -> AppData {
        var data = AppData()
        for event in events { data.rules[event.id] = .init(flexibility: .movable, minimumMinutes: 1,
            travelBeforeMinutes: 0, travelAfterMinutes: 0, travelConfirmed: true) }
        return data
    }
    func testObservedOverlapProducesOneLocalSignalWithoutWrites() {
        let events = [event("a"), event("b", start: 5400, end: 9000)], data = data(events)
        let signals = CoachAgendaSignals.make(events: events, data: data, now: now)
        XCTAssertEqual(signals.count, 1); XCTAssertEqual(signals.first?.events.map(\.id), ["a", "b"])
        XCTAssertTrue(data.moves.isEmpty); XCTAssertTrue(data.coachState.messages.isEmpty)
    }
    func testConfirmedTravelMakesOtherwiseAdjacentAppointmentsConflict() {
        let events = [event("a"), event("b", start: 7500, end: 10000)]
        var data = data(events); data.rules["a"]?.travelAfterMinutes = 10
        XCTAssertEqual(CoachAgendaSignals.make(events: events, data: data, now: now).count, 1)
    }
    func testMissingTravelAsksForEvidenceWithoutInventingAnEta() {
        var source = event("a"); source.location = "Destinazione QA"
        var data = data([source]); data.rules["a"]?.travelConfirmed = false
        let signals = CoachAgendaSignals.make(events: [source], data: data, now: now)
        XCTAssertEqual(signals.count, 1)
        if case .unconfirmedTravel? = signals.first?.kind {} else { XCTFail("Must ask for route review") }
    }
    func testPastPendingActivityIsNotInferredMissedOrScheduledForRecovery() {
        let events = [event("past", start: -7200, end: -3600)], data = data(events)
        XCTAssertTrue(CoachAgendaSignals.make(events: events, data: data, now: now).isEmpty)
        XCTAssertTrue(data.records.isEmpty)
    }
    func testRefreshWithChangedExternalTimeRemovesTheOldConflict() {
        var events = [event("a"), event("b", start: 5400, end: 9000)]
        let data = data(events)
        XCTAssertEqual(CoachAgendaSignals.make(events: events, data: data, now: now).count, 1)
        events[1].start = now.addingTimeInterval(10000); events[1].end = now.addingTimeInterval(13600)
        XCTAssertTrue(CoachAgendaSignals.make(events: events, data: data, now: now).isEmpty)
    }
    func testDistantDaysAndAllDayItemsDoNotBecomeCertainTravelConflicts() {
        var allDay = event("all"); allDay.isAllDay = true
        let events = [allDay, event("a"), event("tomorrow", start: 86400, end: 90000)]
        XCTAssertTrue(CoachAgendaSignals.make(events: events, data: data(events), now: now).isEmpty)
    }
    func testExactAdjacencyWithoutBuffersIsNotAnOverlap() {
        let events = [event("a"), event("b", start: 7200, end: 10000)]
        XCTAssertTrue(CoachAgendaSignals.make(events: events, data: data(events), now: now).isEmpty)
    }
}
