import XCTest
@testable import PivotCore

final class CoachCalendarScopeTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-21T12:00:00+02:00")!
    private func event(_ id: String, offset: Int, kind: EventKind = .other) -> CalendarItem {
        let start = PivotDate.calendar.date(byAdding: .day, value: offset, to: now)!
        return .init(id: id, eventIdentifier: id, calendarIdentifier: "calendar-secret-qa", calendarTitle: "Calendar secret QA",
            title: "Private title " + id, start: start, end: start.addingTimeInterval(3600), location: "Private address QA",
            notes: "Private notes QA", colorHex: "#00AA99", isAllDay: false, writable: true, kind: kind, recurring: false)
    }
    private func snapshot(_ events: [CalendarItem], scope: CoachCalendarScope = .today,
        purpose: String = "conversation", version: Int = 3, data: AppData = AppData()) throws -> CoachV8Snapshot {
        try CoachV8Snapshot.make(message: "Richiesta QA", events: events, data: data, now: now,
            purpose: purpose, protocolVersion: version, calendarScope: scope)
    }
    func testDefaultDoesNotSilentlyIncludeTomorrow() throws {
        let value = try snapshot([event("today", offset: 0), event("tomorrow", offset: 1)])
        XCTAssertEqual(value.calendarScope, .today)
        XCTAssertEqual(value.sources.values.map(\.id), ["today"])
    }
    func testExplicitWeekIncludesSevenCalendarDaysNotAnUnboundedArchive() throws {
        let events = (-1...7).map { event("qa-\($0)", offset: $0) }
        let value = try snapshot(events, scope: .week)
        XCTAssertEqual(value.request.events.count, 7)
        XCTAssertEqual(Set(value.sources.values.map(\.id)), Set((0...6).map { "qa-\($0)" }))
    }
    func testWeeklyContextOmitsRawIdentitiesLocationsNotesAndHealthProvenance() throws {
        let item = event("tomorrow-secret-qa", offset: 1)
        var data = AppData(); var record = EventRecord(id: item.id, snapshot: item)
        record.health = .init(id: "health-secret-qa", start: item.start, end: item.end, type: "strength", durationSeconds: 3600)
        record.healthManagedFields = [.actualStart, .actualEnd]; record.status = .completed; data.records[item.id] = record
        let value = try snapshot([item], scope: .week, data: data)
        let text = String(decoding: value.encodedRequest, as: UTF8.self)
        for secret in ["tomorrow-secret-qa", "Private", "calendar-secret-qa", "Calendar secret QA", "health-secret-qa", "healthManagedFields"] {
            XCTAssertFalse(text.contains(secret), secret)
        }
        XCTAssertEqual(value.request.events.first?.status, .pending)
        XCTAssertLessThanOrEqual(value.encodedRequest.count, 24_000)
    }
    func testRewriteAndLegacyProtocolDoNotInheritExpandedScope() throws {
        let item = event("tomorrow", offset: 1)
        let rewrite = try snapshot([item], scope: .week, purpose: "rewrite")
        XCTAssertTrue(rewrite.request.events.isEmpty); XCTAssertEqual(rewrite.calendarScope, .today)
        let legacy = try snapshot([item], scope: .week, version: 2)
        XCTAssertTrue(legacy.request.events.isEmpty); XCTAssertEqual(legacy.calendarScope, .today)
    }
    func testWeekCannotEvadeExistingEventOrByteLimits() {
        let events = (0..<49).map { index -> CalendarItem in
            var item = event("qa-\(index)", offset: index % 7); item.start.addTimeInterval(Double(index) * 60); return item
        }
        XCTAssertThrowsError(try snapshot(events, scope: .week)) { error in
            guard case CoachV8Error.calendarTooLarge = error else { return XCTFail("Expected actionable calendar limit, got \(error)") }
        }
    }
    func testNarrowingBusyWeekKeepsAllEventsInChosenDayWithoutRelaxingCap() throws {
        let events = (0..<50).map { index in event("qa-\(index)", offset: index == 0 ? 0 : 1 + (index - 1) % 6) }
        XCTAssertThrowsError(try snapshot(events, scope: .week))
        let value = try snapshot(events)
        XCTAssertEqual(value.sources.values.map(\.id), ["qa-0"])
        XCTAssertEqual(value.originalEvents.count, 50, "Local stale-context checks still retain the complete calendar")
    }
    func testAllDayEventsRemainExcluded() throws {
        var item = event("all-day", offset: 1); item.isAllDay = true
        XCTAssertTrue(try snapshot([item], scope: .week).request.events.isEmpty)
    }
    func testFutureMutationNeedsExplicitScopeAndRemainsUncommitted() throws {
        let item = event("tomorrow", offset: 1)
        let edit = CoachCalendarEdit(kind: .delete, eventID: "e0", title: nil, start: nil, end: nil, notes: nil)
        XCTAssertThrowsError(try CoachCalendarBatch.make([edit], sources: ["e0": item], messageID: UUID(), now: now, data: AppData()))
        let value = try CoachCalendarBatch.make([edit], sources: ["e0": item], messageID: UUID(), now: now, data: AppData(), calendarScope: .week)
        XCTAssertEqual(value.status, .pending); XCTAssertEqual(value.actions.first?.source, item)
        let outside = event("outside", offset: 7)
        XCTAssertThrowsError(try CoachCalendarBatch.make([edit], sources: ["e0": outside], messageID: UUID(), now: now, data: AppData(), calendarScope: .week))
    }
    func testTypedFutureResponseUsesTheSameScopeValidation() throws {
        let data = AppData(), item = event("tomorrow", offset: 1)
        let value = try snapshot([item], scope: .week, data: data)
        let edit = CoachCalendarEdit(kind: .delete, eventID: "e0", title: nil, start: nil, end: nil, notes: nil)
        let response = CoachV8Response(version: 3, requestID: value.request.requestID, mode: .actions, eventIDs: [], reply: "Proposta QA", actions: [edit])
        let result = try CoachV8Planner.preview(response, snapshot: value, events: [item], data: data, now: now)
        XCTAssertTrue(result.options.isEmpty)
        XCTAssertTrue(result.reply.contains("non è ancora cambiato"))
    }
    func testFuturePlanCannotTreatFutureWorkoutAsMissedToday() throws {
        var item = event("tomorrow", offset: 1, kind: .workout); item.title = "Palestra QA"
        let data = AppData(), value = try snapshot([item], scope: .week, data: data)
        let response = CoachV8Response(version: 3, requestID: value.request.requestID, mode: .plan, eventIDs: ["e0"], reply: "Proposta QA")
        let result = try CoachV8Planner.preview(response, snapshot: value, events: [item], data: data, now: now)
        XCTAssertTrue(result.options.isEmpty); XCTAssertTrue(result.reply.contains("altro giorno"))
    }
    func testSevenDaysAcrossDSTUseCalendarBoundaries() {
        let before = ISO8601DateFormatter().date(from: "2026-10-24T23:00:00+02:00")!
        var item = event("boundary", offset: 0)
        item.start = ISO8601DateFormatter().date(from: "2026-10-31T00:00:00+01:00")!; item.end = item.start.addingTimeInterval(60)
        XCTAssertFalse(CoachCalendarScope.week.contains(item, now: before))
        item.start.addTimeInterval(-3600); item.end = item.start.addingTimeInterval(60)
        XCTAssertTrue(CoachCalendarScope.week.contains(item, now: before))
    }
}
