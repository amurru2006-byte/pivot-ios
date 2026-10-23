import XCTest
@testable import PivotCore

final class CoachPlanningSearchTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-19T12:00:00+02:00")!
    private let access = CoachPlanningSelection.Access(calendar: true, online: true)
    private var target: CalendarItem {
        .init(id: "target-search-qa", eventIdentifier: "native-search-qa", calendarIdentifier: "qa", calendarTitle: "QA",
            title: "Attività sintetica QA", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200),
            location: "", notes: "", colorHex: "7EE6CD", isAllDay: false, writable: true, kind: .workout)
    }
    private var data: AppData {
        var value = AppData()
        value.updatedAt = now
        value.settings.quietEndHour = 8; value.settings.quietStartHour = 22
        value.rules[target.id] = .init(flexibility: .movable, minimumMinutes: 60,
            travelBeforeMinutes: 20, travelAfterMinutes: 20, travelConfirmed: true)
        return value
    }
    private var budget: CalendarTimeBudget {
        CalendarTimeBudget.confirmed(activityMinutes: 75, rule: data.rules[target.id]!, preparationMinutes: 10)!
    }
    private func at(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func range(_ start: String, _ end: String) -> DateInterval { .init(start: at(start), end: at(end)) }
    private func selection(events: [CalendarItem]? = nil, data: AppData? = nil, multiple: Bool = false) throws -> CoachPlanningSelection {
        let events = events ?? [target], data = data ?? self.data
        let snapshot = try CoachV8Snapshot.make(message: "Sposta attività QA a giovedì sera", events: events, data: data,
            now: now, purpose: "conversation", protocolVersion: 3, calendarScope: .week)
        let alias = try XCTUnwrap(snapshot.sources.first(where: { $0.value.id == target.id })?.key)
        let intent = CoachPlanningIntent(eventIDs: multiple ? snapshot.sources.keys.sorted() : [alias],
            allowedDayOffsets: [3], excludedDayOffsets: [1, 2], band: .evening,
            earliestMinute: nil, latestMinute: nil, afterEventID: nil)
        return try .prepare(intent, responseRequestID: snapshot.request.requestID, snapshot: snapshot,
            access: access, events: events, data: data, now: now)
    }
    private func find(_ ranges: [DateInterval], events: [CalendarItem]? = nil) -> [CalendarRecoveryWindow] {
        CalendarRecoveryWindows.find(target: target, budget: budget, events: events ?? [target], data: data,
            now: now, days: 7, within: ranges)
    }

    func testConstraintsAreAppliedBeforeThreeResultCapSoThursdayIsNotLost() throws {
        let ranges = [range("2026-10-22T18:00:00+02:00", "2026-10-22T23:00:00+02:00")]
        let window = try XCTUnwrap(find(ranges).first)
        XCTAssertEqual(window.occupiedStart, ranges[0].start)
        XCTAssertEqual(window.activityStart, ranges[0].start.addingTimeInterval(1800))
        XCTAssertEqual(window.occupiedEnd, ranges[0].start.addingTimeInterval(7500))
        XCTAssertLessThanOrEqual(window.occupiedEnd, at("2026-10-22T22:00:00+02:00"))
    }
    func testEntireEnvelopeMustFitAndAnExactFitIsAccepted() {
        let start = at("2026-10-22T18:00:00+02:00")
        XCTAssertTrue(find([.init(start: start, duration: 90.0 * 60)]).isEmpty)
        let exact = find([.init(start: start, duration: 125.0 * 60)])
        XCTAssertEqual(exact.count, 1); XCTAssertEqual(exact.first?.occupiedEnd, start.addingTimeInterval(7500))
    }
    func testSeparateAllowedRangesDoNotBridgeAForbiddenGapOrDuplicateAlternatives() throws {
        let first = range("2026-10-20T08:00:00+02:00", "2026-10-20T09:00:00+02:00")
        let second = range("2026-10-20T15:00:00+02:00", "2026-10-20T18:00:00+02:00")
        let values = find([second, first])
        XCTAssertEqual(values.count, 1); XCTAssertEqual(values.first?.occupiedStart, second.start)
    }
    func testEmptyOverlappingDuplicateZeroAndTooManyRangesAreRejected() {
        let r = range("2026-10-20T08:00:00+02:00", "2026-10-20T18:00:00+02:00")
        for ranges in [[], [r, r], [r, .init(start: r.start.addingTimeInterval(3600), duration: 3600)],
                       [.init(start: r.start, duration: 0)], Array(repeating: r, count: 8)] {
            XCTAssertTrue(find(ranges).isEmpty)
        }
    }
    func testBusyBlockAndReturnTravelWithinAllowedRangeAreNotIgnored() throws {
        var other = target; other.id = "block-qa"; other.eventIdentifier = "native-block-qa"
        other.start = at("2026-10-22T18:30:00+02:00"); other.end = at("2026-10-22T19:30:00+02:00")
        let r = range("2026-10-22T18:00:00+02:00", "2026-10-22T22:00:00+02:00")
        let window = try XCTUnwrap(find([r], events: [target, other]).first)
        XCTAssertEqual(window.occupiedStart, other.end)
        XCTAssertEqual(window.occupiedEnd.timeIntervalSince(window.occupiedStart), 7500)
    }
    func testLocalAdapterUsesFreshBoundIntentAndDoesNotChangeCalendarOrFunds() throws {
        let events = [target], data = data, before = try BackupCodec.encode(data)
        let selected = try selection(events: events, data: data)
        let values = try CoachPlanningSearch.alternatives(for: selected, budget: budget, access: access,
            events: events, data: data, now: now)
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.occupiedStart, at("2026-10-22T18:00:00+02:00"))
        XCTAssertEqual(try BackupCodec.encode(data), before)
        XCTAssertEqual(events, [target]); XCTAssertTrue(data.moves.isEmpty)
    }
    func testSearchRevalidatesPermissionExpiryAndNewPendingWorkEvenWithoutRevisionBump() throws {
        let selected = try selection()
        XCTAssertThrowsError(try CoachPlanningSearch.alternatives(for: selected, budget: budget,
            access: .init(calendar: false, online: true), events: [target], data: data, now: now)) { error in
            XCTAssertEqual(error as? CoachPlanningSelection.Failure, .accessRevoked)
        }
        XCTAssertThrowsError(try CoachPlanningSearch.alternatives(for: selected, budget: budget,
            access: access, events: [target], data: data, now: now.addingTimeInterval(121))) { error in
            XCTAssertEqual(error as? CoachPlanningSelection.Failure, .staleContext)
        }
        var changed = data
        changed.moves = [.init(source: target, proposedStart: target.start.addingTimeInterval(86400), proposedEnd: target.end.addingTimeInterval(86400))]
        XCTAssertThrowsError(try CoachPlanningSearch.alternatives(for: selected, budget: budget,
            access: access, events: [target], data: changed, now: now)) { error in
            XCTAssertEqual(error as? CoachPlanningSelection.Failure, .pendingReview)
        }
    }
    func testUnknownTravelCannotBecomeZeroAndMultipleTargetsCannotBeIndependentOverlappingPlans() throws {
        var unknown = data; unknown.rules[target.id]?.travelConfirmed = false
        let selected = try selection(data: unknown)
        XCTAssertThrowsError(try CoachPlanningSearch.alternatives(for: selected, budget: budget,
            access: access, events: [target], data: unknown, now: now)) { error in
            XCTAssertEqual(error as? CoachPlanningSearch.Failure, .reviewRequired)
        }
        var other = target; other.id = "second-qa"; other.eventIdentifier = "native-second-qa"
        other.start.addTimeInterval(7200); other.end.addTimeInterval(7200)
        var multiple = data; multiple.rules[other.id] = multiple.rules[target.id]
        let group = try selection(events: [target, other], data: multiple, multiple: true)
        XCTAssertThrowsError(try CoachPlanningSearch.alternatives(for: group, budget: budget,
            access: access, events: [target, other], data: multiple, now: now)) { error in
            XCTAssertEqual(error as? CoachPlanningSearch.Failure, .jointPlanningRequired)
        }
    }
    func testInconsistentTravelBudgetCannotReplaceConfirmedLogistics() throws {
        let selected = try selection()
        var invalid = budget; invalid.travelBeforeMinutes = 0
        let values = try CoachPlanningSearch.alternatives(for: selected, budget: invalid, access: access,
            events: [target], data: data, now: now)
        XCTAssertTrue(values.isEmpty)
    }
}
