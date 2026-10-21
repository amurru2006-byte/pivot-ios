import XCTest
@testable import PivotCore

final class CalendarSynchronizationTests: XCTestCase {
    func testExplicitEndOnlyEditProposesPlannedStartWithoutInventingMeasuredStartOrOutcome() throws {
        let start = date("2026-10-20T13:30:00+02:00")
        let item = event(start: start, end: date("2026-10-20T14:30:00+02:00"))
        var record = EventRecord(id: item.id, snapshot: item)
        record.actualEnd = date("2026-10-20T17:30:00+02:00")
        XCTAssertNil(CalendarSynchronization.explicitlyEditedTiming(for: record, event: item))
        record.calendarTimingNeedsConfirmation = true
        let proposal = try XCTUnwrap(CalendarSynchronization.explicitlyEditedTiming(for: record, event: item))
        XCTAssertEqual(proposal.start, start); XCTAssertEqual(proposal.end, record.actualEnd)
        XCTAssertNil(record.actualStart); XCTAssertEqual(record.status, .pending)
        XCTAssertTrue(CalendarSynchronization.needsCalendarUpdate(proposal, event: item))
        XCTAssertNil(CalendarSynchronization.actualTiming(for: record, event: item), "Proposal still needs an explicit user confirmation")
        let restored = try JSONDecoder().decode(EventRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(CalendarSynchronization.explicitlyEditedTiming(for: restored, event: item), proposal)
        var legacy = record
        legacy.calendarTimingNeedsConfirmation = nil; legacy.timingFromCalendar = false
        XCTAssertEqual(CalendarSynchronization.explicitlyEditedTiming(for: legacy, event: item), proposal,
            "A correction saved by an older app can be reviewed without re-entering it or silently changing Calendar")
    }
    func testExplicitTimingRejectsInvalidEndpointsRunningSkippedAndAllDay() {
        let start = date("2026-10-20T13:30:00+02:00")
        var item = event(start: start, end: start.addingTimeInterval(3600))
        var record = EventRecord(id: item.id, snapshot: item)
        record.calendarTimingNeedsConfirmation = true
        XCTAssertNil(CalendarSynchronization.explicitlyEditedTiming(for: record, event: item))
        record.actualEnd = start.addingTimeInterval(-1)
        XCTAssertNil(CalendarSynchronization.explicitlyEditedTiming(for: record, event: item))
        record.actualEnd = start.addingTimeInterval(7200)
        for status in [Completion.running, .skipped] {
            record.status = status
            XCTAssertNil(CalendarSynchronization.explicitlyEditedTiming(for: record, event: item))
        }
        record.status = .completed; item.isAllDay = true
        XCTAssertNil(CalendarSynchronization.explicitlyEditedTiming(for: record, event: item))
        item.isAllDay = false; record.actualEnd = Date(timeIntervalSinceReferenceDate: .infinity)
        XCTAssertNil(CalendarSynchronization.explicitlyEditedTiming(for: record, event: item))
    }
    func testSavingHealthObservationsDoesNotSilentlyCopyThemToCalendarButExplicitEditCanBeReviewed() throws {
        let start = date("2026-10-20T13:30:00+02:00")
        let item = event(start: start, end: start.addingTimeInterval(3600))
        var record = EventRecord(id: item.id, snapshot: item, status: .completed,
            actualStart: start.addingTimeInterval(60), actualEnd: start.addingTimeInterval(7200))
        record.health = .init(id: "synthetic-health-source", start: record.actualStart!, end: record.actualEnd!,
            type: "strength", durationSeconds: 7140, distanceKM: nil, activeCalories: nil, averageBPM: nil, elevationM: nil)
        XCTAssertNil(CalendarSynchronization.actualTiming(for: record, event: item))
        record.health = nil; record.healthSleep = SleepRecord()
        XCTAssertNil(CalendarSynchronization.actualTiming(for: record, event: item))
        XCTAssertNil(CalendarSynchronization.explicitlyEditedTiming(for: record, event: item))
        record.calendarTimingNeedsConfirmation = true
        XCTAssertNotNil(CalendarSynchronization.explicitlyEditedTiming(for: record, event: item), "A proposal still needs the separate Calendar confirmation")
    }
    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func event(start: Date, end: Date, writable: Bool = true, allDay: Bool = false) -> CalendarItem {
        CalendarItem(id: "calendar|event", eventIdentifier: "event", calendarIdentifier: "calendar",
                     calendarTitle: "Personale", title: "Lezione", start: start, end: end,
                     location: "", notes: "", colorHex: "#123456", isAllDay: allDay,
                     writable: writable, kind: .tutoring)
    }

    func testCompletedRealTimesProduceOnlyTheRequestedOccurrenceTiming() {
        let plannedStart = date("2026-10-12T08:00:00+02:00")
        let plannedEnd = date("2026-10-12T09:00:00+02:00")
        let item = event(start: plannedStart, end: plannedEnd)
        var record = EventRecord(id: item.id, snapshot: item)
        record.status = .completed
        record.actualStart = date("2026-10-12T08:10:00+02:00")
        record.actualEnd = date("2026-10-12T09:20:00+02:00")

        let timing = CalendarSynchronization.actualTiming(for: record, event: item)
        XCTAssertEqual(timing?.start, record.actualStart)
        XCTAssertEqual(timing?.end, record.actualEnd)
        XCTAssertTrue(CalendarSynchronization.needsCalendarUpdate(timing!, event: item))
    }

    func testPendingRunningSkippedAndAllDayNeverWriteCalendarTimes() {
        let start = date("2026-10-12T08:00:00+02:00")
        let item = event(start: start, end: start.addingTimeInterval(3600))
        for status in [Completion.pending, .running, .skipped] {
            var record = EventRecord(id: item.id, snapshot: item)
            record.status = status; record.actualStart = start; record.actualEnd = start.addingTimeInterval(1800)
            XCTAssertNil(CalendarSynchronization.actualTiming(for: record, event: item))
        }
        var completed = EventRecord(id: item.id, snapshot: item)
        completed.status = .completed; completed.actualStart = start; completed.actualEnd = start.addingTimeInterval(1800)
        XCTAssertNil(CalendarSynchronization.actualTiming(for: completed, event: event(start: start, end: start.addingTimeInterval(3600), allDay: true)))
    }

    func testUnchangedActualTimesAreANoOp() {
        let start = date("2026-10-12T08:00:00+02:00")
        let item = event(start: start, end: start.addingTimeInterval(3600))
        var record = EventRecord(id: item.id, snapshot: item)
        record.status = .completed; record.actualStart = item.start; record.actualEnd = item.end
        let timing = CalendarSynchronization.actualTiming(for: record, event: item)!
        XCTAssertFalse(CalendarSynchronization.needsCalendarUpdate(timing, event: item))
    }

    func testCalendarSuggestionsAreNeverWrittenBackAsMeasuredTimes() {
        let start = date("2026-10-12T08:00:00+02:00")
        let item = event(start: start, end: start.addingTimeInterval(3600))
        var record = EventRecord(id: item.id, snapshot: item)
        record.status = .completed
        record.actualStart = start; record.actualEnd = start.addingTimeInterval(3600)
        record.timingFromCalendar = true
        XCTAssertNil(CalendarSynchronization.actualTiming(for: record, event: item))
    }

    func testDeletedPendingSnapshotIsNotHistoryButARealAnswerIs() {
        let start = date("2026-10-12T08:00:00+02:00")
        let item = event(start: start, end: start.addingTimeInterval(3600))
        let pending = EventRecord(id: item.id, snapshot: item)
        XCTAssertFalse(CalendarSynchronization.hasMeaningfulHistory(pending))

        var answered = pending
        answered.status = .skipped; answered.reason = "Lezione annullata"
        XCTAssertTrue(CalendarSynchronization.hasMeaningfulHistory(answered))

        var noted = pending
        noted.notes = "Dato inserito da me"
        XCTAssertTrue(CalendarSynchronization.hasMeaningfulHistory(noted))
    }

    func testEventNotificationsAreQueuedOnlyWithinThirtySixHours() {
        let now = date("2026-10-12T08:00:00+02:00")
        let soon = event(start: now.addingTimeInterval(24 * 3600), end: now.addingTimeInterval(25 * 3600))
        var later = event(start: now.addingTimeInterval(3 * 86400), end: now.addingTimeInterval(3 * 86400 + 3600))
        later.id = "calendar|later"; later.eventIdentifier = "later"
        let requests = NotificationPlan.requests(events: [soon, later], data: AppData(), now: now)
        XCTAssertTrue(requests.contains { $0.eventID == soon.id })
        XCTAssertFalse(requests.contains { $0.eventID == later.id })
    }
}
