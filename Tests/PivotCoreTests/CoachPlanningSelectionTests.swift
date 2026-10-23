import XCTest
@testable import PivotCore

final class CoachPlanningSelectionTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-19T12:00:00+02:00")!
    private let access = CoachPlanningSelection.Access(calendar: true, online: true)
    private var target: CalendarItem {
        .init(id: "target-qa", eventIdentifier: "native-target-qa", calendarIdentifier: "calendar-qa", calendarTitle: "QA",
            title: "Allenamento sintetico QA", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200),
            location: "", notes: "Nota locale QA", colorHex: "7EE6CD", isAllDay: false, writable: true, kind: .workout)
    }
    private var data: AppData {
        var result = AppData()
        result.rules[target.id] = .init(flexibility: .movable, minimumMinutes: 60, travelConfirmed: true)
        return result
    }
    private func context(events: [CalendarItem], data: AppData) throws -> CoachV8Snapshot {
        try .make(message: "Organizza attività QA", events: events, data: data, now: now,
            purpose: "conversation", protocolVersion: 3, calendarScope: .week)
    }
    private func intent(_ alias: String = "e0") -> CoachPlanningIntent {
        .init(eventIDs: [alias], allowedDayOffsets: [1, 3], excludedDayOffsets: [2],
            band: .evening, earliestMinute: nil, latestMinute: nil, afterEventID: nil)
    }
    private func prepare(_ intent: CoachPlanningIntent = .init(eventIDs: ["e0"], allowedDayOffsets: [1], excludedDayOffsets: [], band: nil, earliestMinute: nil, latestMinute: nil, afterEventID: nil),
                         events: [CalendarItem]? = nil, data: AppData? = nil) throws -> CoachPlanningSelection {
        let events = events ?? [target], data = data ?? self.data, snapshot = try context(events: events, data: data)
        return try .prepare(intent, responseRequestID: snapshot.request.requestID, snapshot: snapshot, access: access, events: events, data: data, now: now)
    }

    func testBindingReturnsLocalSourcesAndAllowedRangesWithoutAnyCalendarOrMoneyMutation() throws {
        let data = data, events = [target], snapshot = try context(events: events, data: data)
        let selected = try CoachPlanningSelection.prepare(intent(), responseRequestID: snapshot.request.requestID,
            snapshot: snapshot, access: access, events: events, data: data, now: now)
        XCTAssertEqual(selected.sources, events); XCTAssertTrue(selected.maySearchLocally)
        XCTAssertEqual(selected.allowedIntervals.map { PivotDate.key($0.start) }, ["2026-10-20", "2026-10-22"])
        XCTAssertTrue(selected.unconfirmedTravelIDs.isEmpty); XCTAssertTrue(selected.pairedReviewIDs.isEmpty)
        XCTAssertTrue(data.moves.isEmpty); XCTAssertTrue(data.payments.isEmpty); XCTAssertTrue(data.records.isEmpty)
        XCTAssertTrue(data.coachState.pendingCalendarChanges.isEmpty); XCTAssertNil(data.coachState.calendarBatches)
        XCTAssertEqual(snapshot.request.version, 3, "This intake prototype does not silently change the deployed protocol")
    }

    func testWrongRequestIdentityExpiredDayAndChangedDataAreRejected() throws {
        let data = data, events = [target], snapshot = try context(events: events, data: data)
        XCTAssertThrowsError(try CoachPlanningSelection.prepare(intent(), responseRequestID: UUID().uuidString, snapshot: snapshot, access: access, events: events, data: data, now: now))
        for later in [now.addingTimeInterval(121), now.addingTimeInterval(86400)] {
            XCTAssertThrowsError(try CoachPlanningSelection.prepare(intent(), responseRequestID: snapshot.request.requestID, snapshot: snapshot, access: access, events: events, data: data, now: later))
        }
        var changed = data; changed.updatedAt.addTimeInterval(1)
        XCTAssertThrowsError(try CoachPlanningSelection.prepare(intent(), responseRequestID: snapshot.request.requestID, snapshot: snapshot, access: access, events: events, data: changed, now: now))
    }

    func testExternalCalendarChangeOrDeletedTargetIsNotAcceptedUnderOldAliases() throws {
        let data = data, snapshot = try context(events: [target], data: data)
        var changed = target; changed.location = "Nuovo luogo sintetico QA"
        for events in [[], [changed]] {
            XCTAssertThrowsError(try CoachPlanningSelection.prepare(intent(), responseRequestID: snapshot.request.requestID, snapshot: snapshot, access: access, events: events, data: data, now: now))
        }
    }

    func testUnknownAliasReadonlyActivityAndFixedRuleCannotBecomeAMove() throws {
        XCTAssertThrowsError(try prepare(intent("e1")))
        var readonly = target; readonly.writable = false
        XCTAssertThrowsError(try prepare(intent(), events: [readonly]))
        var fixed = data; fixed.rules[target.id]?.flexibility = .fixed
        XCTAssertThrowsError(try prepare(intent(), data: fixed))
    }

    func testRunningCompletedAndPartialStatusesAreIneligibleButPendingIsNotAssumedMissed() throws {
        for status in [Completion.running, .completed, .partial] {
            var data = data; data.records[target.id] = .init(id: target.id, snapshot: target, status: status)
            XCTAssertThrowsError(try prepare(intent(), data: data))
        }
        let pending = try prepare(intent())
        XCTAssertEqual(pending.sources[0].id, target.id)
        XCTAssertTrue(data.records.isEmpty, "Intake cannot mark a future/pending event skipped")
    }

    func testMissingTravelConfirmationRemainsAReviewRequirementNotZeroMinutes() throws {
        var data = data; data.rules[target.id]?.travelConfirmed = false
        let selected = try prepare(intent(), data: data)
        XCTAssertFalse(selected.maySearchLocally); XCTAssertEqual(selected.unconfirmedTravelIDs, [target.id])
        XCTAssertTrue(data.moves.isEmpty)
    }

    func testPendingLocalMoveOrNativeBatchMustBeReviewedBeforeAnotherPlan() throws {
        var moved = data
        moved.moves = [.init(source: target, proposedStart: target.start.addingTimeInterval(86400), proposedEnd: target.end.addingTimeInterval(86400))]
        XCTAssertThrowsError(try prepare(intent(), data: moved))
        var pending = data
        let message = CoachMessage(dayKey: PivotDate.key(now), role: .coach, text: "Anteprima QA", createdAt: now)
        pending.coachState.messages = [message]
        pending.coachState.calendarBatches = [.init(messageID: message.id, dayKey: message.dayKey, createdAt: now,
            actions: [.init(kind: .delete, source: target, after: nil)])]
        XCTAssertThrowsError(try prepare(intent(), data: pending))
    }

    func testLinkedJourneyIsFlaggedInsteadOfBypassingThePairedReview() throws {
        var activity = target; activity.location = "Destinazione sintetica QA"
        var journey = activity; journey.id = "trip-qa"; journey.eventIdentifier = "native-trip-qa"; journey.title = "Spostamento"
        journey.start = activity.start.addingTimeInterval(-1800); journey.end = activity.start; journey.kind = .other
        var data = data
        let link = CalendarActivityLink(id: UUID(), activity: activity, travel: journey,
            settings: .init(minutes: 30, origin: "Origine sintetica QA"), capturedAt: now)
        XCTAssertTrue(link.isValid); data.calendarActivityLinks = [link]
        let events = [activity, journey], snapshot = try context(events: events, data: data)
        let alias = try XCTUnwrap(snapshot.sources.first(where: { $0.value.id == activity.id })?.key)
        let selected = try CoachPlanningSelection.prepare(intent(alias), responseRequestID: snapshot.request.requestID,
            snapshot: snapshot, access: access, events: events, data: data, now: now)
        XCTAssertEqual(selected.pairedReviewIDs, [activity.id]); XCTAssertFalse(selected.maySearchLocally)
        XCTAssertTrue(data.moves.isEmpty)
    }

    func testAProvidedReferenceUsesTheBoundNativeEndNotAModelAuthoredHour() throws {
        var reference = target; reference.id = "reference-qa"; reference.eventIdentifier = "native-reference-qa"
        reference.title = "Riferimento sintetico QA"; reference.kind = .meal
        reference.start = now.addingTimeInterval(86400 + 6 * 3600); reference.end = reference.start.addingTimeInterval(3600)
        let events = [target, reference], data = data, snapshot = try context(events: events, data: data)
        let ref = try XCTUnwrap(snapshot.sources.first(where: { $0.value.id == reference.id })?.key)
        var requested = intent(); requested.afterEventID = ref
        let selected = try CoachPlanningSelection.prepare(requested, responseRequestID: snapshot.request.requestID,
            snapshot: snapshot, access: access, events: events, data: data, now: now)
        XCTAssertEqual(selected.reference, reference); XCTAssertEqual(selected.allowedIntervals.first?.start, reference.end)
    }

    func testRewriteModeAndInvalidClocksCannotReachCalendarArithmetic() throws {
        let data = data, events = [target]
        let rewrite = try CoachV8Snapshot.make(message: "Riordina questo testo QA", events: events, data: data, now: now, purpose: "rewrite")
        XCTAssertThrowsError(try CoachPlanningSelection.prepare(intent(), responseRequestID: rewrite.request.requestID, snapshot: rewrite, access: access, events: events, data: data, now: now))
        let snapshot = try context(events: events, data: data)
        for invalid in [Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity), now.addingTimeInterval(-1)] {
            XCTAssertThrowsError(try CoachPlanningSelection.prepare(intent(), responseRequestID: snapshot.request.requestID, snapshot: snapshot, access: access, events: events, data: data, now: invalid))
        }
        let selected = try prepare(intent())
        XCTAssertFalse(selected.isCurrent(access: access, events: events, data: data, now: Date(timeIntervalSince1970: .nan)))
        XCTAssertFalse(selected.isCurrent(access: access, events: [], data: data, now: now))
    }

    func testRevokingEitherPermissionStopsIntakeAndInvalidatesPreparedSelection() throws {
        let events = [target], data = data, snapshot = try context(events: events, data: data)
        let selected = try prepare(intent())
        let denied: [CoachPlanningSelection.Access] = [.init(calendar: false, online: true), .init(calendar: true, online: false)]
        for permissions in denied {
            XCTAssertThrowsError(try CoachPlanningSelection.prepare(intent(), responseRequestID: snapshot.request.requestID,
                snapshot: snapshot, access: permissions, events: events, data: data, now: now)) { error in
                XCTAssertEqual(error as? CoachPlanningSelection.Failure, .accessRevoked)
            }
            XCTAssertFalse(selected.isCurrent(access: permissions, events: events, data: data, now: now))
        }
    }
}
