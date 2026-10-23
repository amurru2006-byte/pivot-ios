import XCTest
@testable import PivotCore

final class CoachPlanningAlternativesTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-19T12:00:00+02:00")!
    private func fixture(count: Int = 1, seconds: Double = 3600) throws -> (CoachPlanningSession, [CalendarItem], AppData) {
        var data = AppData(); data.updatedAt = now
        data.settings.quietEndHour = 8; data.settings.quietStartHour = 22
        let events = (0..<count).map { index in
            CalendarItem(id: "local-chain-\(index)-qa", eventIdentifier: "native-chain-\(index)-qa", calendarIdentifier: "qa",
                calendarTitle: "QA", title: "Attività sintetica \(index)", start: now.addingTimeInterval(Double(index + 1) * -7200),
                end: now.addingTimeInterval(Double(index + 1) * -7200 + seconds), location: "", notes: "", colorHex: "7EE6CD",
                isAllDay: false, writable: true, kind: .workout)
        }
        for event in events { data.rules[event.id] = .init(flexibility: .movable, minimumMinutes: 1,
            travelBeforeMinutes: 10, travelAfterMinutes: 15, travelConfirmed: true) }
        let snap = try CoachV8Snapshot.make(message: "Recupero QA", events: events, data: data, now: now,
            purpose: "conversation", protocolVersion: 4, calendarScope: .week)
        let aliases = events.map { event in snap.sources.first { $0.value.id == event.id }!.key }
        let intent = CoachPlanningIntent(eventIDs: aliases, allowedDayOffsets: [1, 3, 4], excludedDayOffsets: [2],
            band: .afternoon, earliestMinute: nil, latestMinute: nil, afterEventID: nil)
        let response = CoachV8Response(version: 4, requestID: snap.request.requestID, mode: .recover, eventIDs: [], reply: "QA", actions: [], planning: intent)
        let session = try CoachPlanningSession.make(response, snapshot: snap, messageID: UUID(), userMessageID: UUID(),
            access: .init(calendar: true, online: true), events: events, data: data, now: now)
        data.coachState.messages = [
            .init(id: session.userMessageID, dayKey: session.dayKey, role: .user, text: "QA", onlineHistoryEligible: true),
            .init(id: session.messageID, dayKey: session.dayKey, role: .coach, text: "QA", onlineHistoryEligible: false)
        ]
        var state = data.coachState; try CoachPlanningStore.save(session, in: &state); data.coachState = state
        return (session, events, data)
    }
    private func options(_ session: CoachPlanningSession, _ events: [CalendarItem], _ data: AppData, at time: Date? = nil) throws -> [CoachOption] {
        try CoachPlanningAlternatives.options(for: session, calendarAccess: true, events: events,
            data: data, now: time ?? now, preparationIncluded: true)
    }
    func testThreeActivitySearchKeepsOrderFullDurationsAndAllTravelWithoutWrites() throws {
        let (session, events, data) = try fixture(count: 3), before = data
        let result = try options(session, events, data)
        XCTAssertFalse(result.isEmpty); XCTAssertLessThanOrEqual(result.count, 3)
        for option in result {
            XCTAssertEqual(option.moves.map { $0.source.id }, events.map(\.id))
            XCTAssertNil(CoachPlanner.validate(option, events: events, data: data, now: now))
            for move in option.moves { XCTAssertEqual(move.proposedEnd.timeIntervalSince(move.proposedStart), 3600) }
            for pair in zip(option.moves, option.moves.dropFirst()) {
                XCTAssertGreaterThanOrEqual(pair.1.proposedStart.timeIntervalSince(pair.0.proposedEnd), 25 * 60)
            }
        }
        XCTAssertEqual(data.updatedAt, before.updatedAt); XCTAssertTrue(data.moves.isEmpty); XCTAssertTrue(data.payments.isEmpty)
    }
    func testLocalReopeningNeedsCalendarButNotAnOnlinePermissionOrAProviderCall() throws {
        let (session, events, data) = try fixture()
        let selection = try CoachPlanningSelection.restore(session, calendarAccess: true, events: events, data: data, now: now)
        XCTAssertTrue(selection.isCurrent(access: .init(calendar: true, online: false), events: events, data: data, now: now))
        XCTAssertNoThrow(try selection.revalidated(access: .init(calendar: true, online: false), events: events, data: data, now: now))
        XCTAssertThrowsError(try CoachPlanningSelection.restore(session, calendarAccess: false, events: events, data: data, now: now))
    }
    func testLocalReopeningDoesNotInheritCloudCalendarOrSharedMemoryLimits() throws {
        let (session, events, initial) = try fixture()
        var data = initial
        let many = events + (0..<60).map { index -> CalendarItem in
            var item = events[0]; item.id = "busy-extra-\(index)-qa"; item.eventIdentifier = "native-extra-\(index)-qa"
            item.start = now.addingTimeInterval(2 * 86400 + Double(index) * 60); item.end = item.start.addingTimeInterval(3600)
            return item
        }
        data.coachState.memories = [.init(text: "Preferenza privata QA", onlineSharingAllowed: false)]
        let snapshot = try CoachV8Snapshot.localPlanning(session, events: many, data: data, now: now)
        XCTAssertEqual(snapshot.request.events.count, 1); XCTAssertTrue(snapshot.request.history.isEmpty)
        XCTAssertTrue(snapshot.request.memories.isEmpty); XCTAssertTrue(snapshot.encodedRequest.isEmpty)
        XCTAssertFalse(try options(session, many, data).isEmpty)
    }
    func testMidnightSearchRetainsOriginalAllowedTuesdayNotShiftedWednesday() throws {
        let (session, events, data) = try fixture(), tomorrow = now.addingTimeInterval(86400)
        let result = try options(session, events, data, at: tomorrow)
        XCTAssertTrue(result.contains { PivotDate.calendar.isDate($0.moves[0].proposedStart, inSameDayAs: tomorrow) })
        let forbidden = now.addingTimeInterval(2 * 86400)
        XCTAssertFalse(result.contains { PivotDate.calendar.isDate($0.moves[0].proposedStart, inSameDayAs: forbidden) })
    }
    func testPreparationAndUnknownTravelRequireReviewInsteadOfPretendingNoSpace() throws {
        let (session, events, data) = try fixture()
        XCTAssertThrowsError(try CoachPlanningAlternatives.options(for: session, calendarAccess: true, events: events,
            data: data, now: now, preparationIncluded: false))
        var unknown = data; unknown.rules[events[0].id]?.travelConfirmed = false
        XCTAssertThrowsError(try options(session, events, unknown)) { XCTAssertEqual($0 as? CoachPlanningAlternatives.Failure, .logistics) }
    }
    func testStageIsLocalRequiresReviewAndNeverChangesIncomeOrNativeEvents() throws {
        let (session, events, initial) = try fixture(count: 2), option = try XCTUnwrap(options(session, events, initial).first)
        var data = initial
        try CoachPlanningAlternatives.stage(option, session: session, calendarAccess: true, events: events, data: &data,
            now: now.addingTimeInterval(1), preparationIncluded: true, routesReviewed: true)
        XCTAssertEqual(data.moves.count, 2); XCTAssertEqual(data.coachState.pendingCalendarChanges.count, 2)
        XCTAssertNil(data.coachState.focusedPlanningSessionID); XCTAssertEqual(data.coachState.planningSessions?.first?.status, .staged)
        XCTAssertTrue(data.moves.allSatisfy { !$0.syncedToCalendar }); XCTAssertEqual(data.payments.count, initial.payments.count)
        XCTAssertNoThrow(try BackupCodec.decode(BackupCodec.encode(data)))
    }
    func testFailedStageIsAtomicForExpiredReviewChangedCalendarAndForgedConstraints() throws {
        let (session, events, initial) = try fixture(), option = try XCTUnwrap(options(session, events, initial).first)
        for scenario in 0..<5 {
            var data = initial, changed = events, proposal = option
            if scenario == 2 { changed[0].title = "Modified QA" }
            if scenario == 3 { proposal.moves[0].proposedStart.addTimeInterval(86400); proposal.moves[0].proposedEnd.addTimeInterval(86400) }
            if scenario == 4 { proposal.moves[0].proposedEnd.addTimeInterval(-60) }
            XCTAssertThrowsError(try CoachPlanningAlternatives.stage(proposal, session: session, calendarAccess: true,
                events: changed, data: &data, now: now.addingTimeInterval(scenario == 0 ? 121 : 1),
                preparationIncluded: true, routesReviewed: scenario != 1))
            XCTAssertTrue(data.moves.isEmpty); XCTAssertTrue(data.coachState.pendingCalendarChanges.isEmpty)
            XCTAssertEqual(data.coachState.planningSessions, initial.coachState.planningSessions)
        }
    }
    func testFractionalMinuteActivityIsNotShortenedAndStaleStoredSessionIsRejected() throws {
        let (session, events, initial) = try fixture(seconds: 3601), option = try XCTUnwrap(options(session, events, initial).first)
        XCTAssertEqual(option.moves[0].proposedEnd.timeIntervalSince(option.moves[0].proposedStart), 3601)
        var missing = initial; missing.coachState.planningSessions = nil; missing.coachState.focusedPlanningSessionID = nil
        XCTAssertThrowsError(try options(session, events, missing))
    }
}
