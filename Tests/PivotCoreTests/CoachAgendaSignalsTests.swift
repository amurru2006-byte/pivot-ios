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
private func linked(_ id: String = "linked", start: Double = 3600) -> ([CalendarItem], AppData) {
        var main = event(id, start: start, end: start + 3600)
        main.location = "Destinazione QA"; main.sourceIdentifier = "source-qa"; main.recurring = false
        var trip = main; trip.id = id + "-trip"; trip.eventIdentifier = "native-" + trip.id
        trip.title = "Viaggio QA"; trip.kind = .other
        trip.start = main.start.addingTimeInterval(-1200); trip.end = main.start
        var value = data([main])
        var options = CalendarCreationOptions(); options.location = main.location
        options.travel = .init(minutes: 20, origin: "Origine QA")
        XCTAssertTrue(CalendarActivityLinks.capture(id: UUID(), receipt: .init(activity: main, travel: trip),
            options: options, data: &value, now: now))
        return ([main, trip], value)
    }
    func testLinkedActivityAndItsJourneyAreOneGroupWithoutInternalFalseConflict() {
        let (events, data) = linked()
        let report = CoachAgendaSignals.report(events: events, data: data, now: now)
        XCTAssertTrue(report.signals.isEmpty); XCTAssertEqual(report.reviewedGroups, 1)
        XCTAssertEqual(report.coverage, .observedToday)
    }
    func testLinkedOutboundJourneyConflictsWithThirdAppointmentEvenWhenActivityDoesNot() {
        let (events, initial) = linked()
        let other = event("third", start: 2700, end: 3300)
        var data = initial
        data.rules[other.id] = .init(flexibility: .fixed, minimumMinutes: 10, travelConfirmed: true)
        let report = CoachAgendaSignals.report(events: events + [other], data: data, now: now)
        XCTAssertEqual(report.totalCount, 1); XCTAssertEqual(report.signals.first?.kind, .overlap)
        XCTAssertEqual(Set(report.signals.first?.events.map(\.id) ?? []), Set((events + [other]).map(\.id)))
        XCTAssertTrue(data.moves.isEmpty); XCTAssertTrue(data.coachState.messages.isEmpty)
    }
    func testConfirmedBufferAndLinkedJourneyAreNotAddedTwice() {
        let (events, initial) = linked()
        var data = initial; data.rules[events[0].id]?.travelBeforeMinutes = 20
        let adjacent = event("adjacent", start: 1800, end: 2400)
        data.rules[adjacent.id] = .init(flexibility: .fixed, minimumMinutes: 10, travelConfirmed: true)
        XCTAssertTrue(CoachAgendaSignals.make(events: events + [adjacent], data: data, now: now).isEmpty)
    }
    func testTwoLinkedGroupsProduceOneConflictBetweenGroups() {
        let (first, a) = linked("first"), (second, b) = linked("second", start: 5400)
        var data = a; data.rules.merge(b.rules, uniquingKeysWith: { _, new in new })
        data.calendarActivityLinks = (a.calendarActivityLinks ?? []) + (b.calendarActivityLinks ?? [])
        let report = CoachAgendaSignals.report(events: first + second, data: data, now: now)
        XCTAssertEqual(report.reviewedGroups, 2); XCTAssertEqual(report.totalCount, 1)
        XCTAssertEqual(report.signals.first?.events.count, 4)
    }
    func testIncompleteLinkedGroupRequiresReviewInsteadOfBeingTreatedAsFree() {
        let (events, data) = linked()
        let report = CoachAgendaSignals.report(events: [events[0]], data: data, now: now)
        XCTAssertEqual(report.coverage, .limited)
        XCTAssertEqual(report.signals.first?.kind, .linkedReview)
        XCTAssertEqual(report.reviewedGroups, 0)
    }
    func testChangedJourneyOrHalfMovedLocalGroupRequiresReview() {
        let (events, initial) = linked()
        var changed = events; changed[1].start.addTimeInterval(-60)
        XCTAssertEqual(CoachAgendaSignals.report(events: changed, data: initial, now: now).signals.first?.kind, .linkedReview)
        var data = initial
        data.moves.append(.init(source: events[0], proposedStart: events[0].start.addingTimeInterval(3600),
                                proposedEnd: events[0].end.addingTimeInterval(3600)))
        XCTAssertEqual(CoachAgendaSignals.report(events: events, data: data, now: now).signals.first?.kind, .linkedReview)
    }
    func testUnconfirmedGroupTravelDeclaresPartialCoverage() {
        let (events, initial) = linked()
        var data = initial; data.rules[events[0].id]?.travelConfirmed = false
        let report = CoachAgendaSignals.report(events: events, data: data, now: now)
        XCTAssertEqual(report.coverage, .limited)
        XCTAssertEqual(report.signals.first?.kind, .unconfirmedTravel)
    }
    func testMissingCalendarAccessDoesNotPretendThereAreNoProblems() {
        let events = [event("a"), event("b")]
        let report = CoachAgendaSignals.report(events: events, data: data(events), now: now, calendarAccess: false)
        XCTAssertEqual(report.coverage, .calendarUnavailable); XCTAssertTrue(report.signals.isEmpty)
        XCTAssertTrue(report.disclosure.contains("non disponibile"))
    }
    func testOversizedAgendaHasExplicitCoverageWithoutSilentTruncation() {
        let events = (0..<97).map { event("large-\($0)") }
        let report = CoachAgendaSignals.report(events: events, data: data(events), now: now)
        XCTAssertEqual(report.coverage, .oversized); XCTAssertTrue(report.signals.isEmpty)
        XCTAssertEqual(report.reviewedGroups, 0)
    }
    func testOnlyThreeVisibleSuggestionsDiscloseTheFullObservationCount() {
        let events = (0..<4).map { event("overlap-\($0)") }
        let report = CoachAgendaSignals.report(events: events, data: data(events), now: now)
        XCTAssertEqual(report.totalCount, 6); XCTAssertEqual(report.signals.count, 3)
        XCTAssertEqual(report.countDisclosure, "Mostro 3 di 6 osservazioni.")
    }
    func testAllDayAvailabilityIsDeclaredUncertainInsteadOfInventedFree() {
        var allDay = event("all"); allDay.isAllDay = true
        let report = CoachAgendaSignals.report(events: [allDay], data: data([allDay]), now: now)
        XCTAssertEqual(report.coverage, .limited); XCTAssertTrue(report.signals.isEmpty)
    }
    func testDiscussRejectsStaleObservationAndRevokedAccessWithoutWrites() throws {
        let events = [event("a"), event("b")]
        let data = data(events)
        let signal = try XCTUnwrap(CoachAgendaSignals.make(events: events, data: data, now: now).first)
        XCTAssertTrue(CoachAgendaSignals.isCurrent(signal, events: events, data: data, now: now, calendarAccess: true))
        var changed = events; changed[1].start.addTimeInterval(20000); changed[1].end.addTimeInterval(20000)
        XCTAssertFalse(CoachAgendaSignals.isCurrent(signal, events: changed, data: data, now: now, calendarAccess: true))
        XCTAssertFalse(CoachAgendaSignals.isCurrent(signal, events: events, data: data, now: now, calendarAccess: false))
        XCTAssertTrue(data.coachState.messages.isEmpty); XCTAssertTrue(data.moves.isEmpty)
    }
    func testDuplicateOrInvalidCalendarTimesDeclareUnverifiableCoverage() {
        let source = event("a")
        XCTAssertEqual(CoachAgendaSignals.report(events: [source, source], data: data([source]), now: now).coverage, .invalid)
        var invalid = source; invalid.end = invalid.start
        XCTAssertEqual(CoachAgendaSignals.report(events: [invalid], data: data([invalid]), now: now).coverage, .invalid)
    }
    func testTomorrowReturnBufferIsComparedOnlyWhenItsConflictTouchesToday() {
        let midnight = PivotDate.calendar.startOfDay(for: now).addingTimeInterval(86400)
        var late = event("late"); late.start = midnight.addingTimeInterval(-1800); late.end = midnight.addingTimeInterval(-60)
        var early = event("early"); early.start = midnight.addingTimeInterval(600); early.end = midnight.addingTimeInterval(4200)
        var data = data([late, early]); data.rules[late.id]?.travelAfterMinutes = 20
        data.rules[early.id]?.travelBeforeMinutes = 15
        let report = CoachAgendaSignals.report(events: [late, early], data: data, now: now)
        XCTAssertEqual(report.totalCount, 1)
    }
}
