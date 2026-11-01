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

    func testDetailedJointSearchKeepsThreeOrderedActivitiesAndReportsItsBound() throws {
        let (session, events, data) = try fixture(count: 3)
        let result = try CoachPlanningAlternatives.search(for: session, calendarAccess: true,
            events: events, data: data, now: now, preparationIncluded: true)
        XCTAssertEqual(result.state, .optionsFound)
        XCTAssertFalse(result.options.isEmpty)
        XCTAssertLessThanOrEqual(result.exploredNodes, 64)
        for option in result.options {
            XCTAssertEqual(option.moves.map { $0.source.id }, events.map(\.id))
            XCTAssertNil(CoachPlanner.validate(option, events: events, data: data, now: now))
        }
        XCTAssertTrue(data.moves.isEmpty)
    }

    func testSearchBudgetExhaustionIsNotReportedAsAnImpossibleAgenda() throws {
        let (session, events, data) = try fixture(count: 2)
        let result = try CoachPlanningAlternatives.search(for: session, calendarAccess: true,
            events: events, data: data, now: now, preparationIncluded: true, maxNodes: 1)
        XCTAssertEqual(result.state, .limitReached)
        XCTAssertEqual(result.exploredNodes, 1)
        XCTAssertTrue(result.options.isEmpty)
        XCTAssertTrue(data.moves.isEmpty)
        XCTAssertTrue(data.coachState.pendingCalendarChanges.isEmpty)
    }

    func testCancellationBeforeSearchReturnsNoProposalOrWrites() throws {
        let (session, events, data) = try fixture(count: 2)
        let result = try CoachPlanningAlternatives.search(for: session, calendarAccess: true,
            events: events, data: data, now: now, preparationIncluded: true, isCancelled: { true })
        XCTAssertEqual(result.state, .cancelled)
        XCTAssertEqual(result.exploredNodes, 0)
        XCTAssertTrue(result.options.isEmpty)
        XCTAssertTrue(data.moves.isEmpty)
    }

    func testCancellationDuringJointSearchDiscardsAllProposals() throws {
        let (session, events, data) = try fixture(count: 3)
        var checks = 0
        let result = try CoachPlanningAlternatives.search(for: session, calendarAccess: true,
            events: events, data: data, now: now, preparationIncluded: true,
            isCancelled: { checks += 1; return checks >= 4 })
        XCTAssertEqual(result.state, .cancelled)
        XCTAssertTrue(result.options.isEmpty)
        XCTAssertGreaterThan(result.exploredNodes, 0)
        XCTAssertTrue(data.moves.isEmpty)
    }

    func testInvalidSearchBoundsAreRejectedRatherThanUnbounded() throws {
        let (session, events, data) = try fixture()
        for bound in [0, -1, 513, Int.max] {
            XCTAssertThrowsError(try CoachPlanningAlternatives.search(for: session, calendarAccess: true,
                events: events, data: data, now: now, preparationIncluded: true, maxNodes: bound)) {
                XCTAssertEqual($0 as? CoachPlanningAlternatives.Failure, .invalid)
            }
        }
    }

    func testEmptyAllowedIntersectionIsDistinctFromCancellationOrSearchLimit() throws {
        let (session, events, initial) = try fixture()
        var data = initial
        data.settings.quietEndHour = 20; data.settings.quietStartHour = 22
        let result = try CoachPlanningAlternatives.search(for: session, calendarAccess: true,
            events: events, data: data, now: now, preparationIncluded: true)
        XCTAssertEqual(result.state, .notFoundWithinSearch)
        XCTAssertTrue(result.options.isEmpty)
        XCTAssertLessThanOrEqual(result.exploredNodes, 64)
    }

    func testWindowCollectorCanExposeLaterDaysWhileDefaultStaysThree() throws {
        let (_, events, data) = try fixture()
        let source = events[0]
        let budget = try XCTUnwrap(CalendarTimeBudget.confirmed(activityMinutes: 60,
            rule: EventRule.effective(for: source, data: data), preparationMinutes: 0))
        let original = CalendarRecoveryWindows.find(target: source, budget: budget, events: events,
            data: data, now: now, days: 7)
        let expanded = CalendarRecoveryWindows.find(target: source, budget: budget, events: events,
            data: data, now: now, days: 7, limit: 4)
        XCTAssertEqual(original.count, 3)
        XCTAssertEqual(expanded.count, 4)
        XCTAssertEqual(Array(expanded.prefix(3)), original)
        XCTAssertTrue(CalendarRecoveryWindows.find(target: source, budget: budget, events: events,
            data: data, now: now, days: 7, limit: Int.max).isEmpty)
    }

    func testDetailedSearchStillRequiresPreparationAndCurrentCalendar() throws {
        let (session, events, data) = try fixture()
        XCTAssertThrowsError(try CoachPlanningAlternatives.search(for: session, calendarAccess: true,
            events: events, data: data, now: now, preparationIncluded: false))
        var changed = events; changed[0].title = "Modifica esterna sintetica"
        XCTAssertThrowsError(try CoachPlanningAlternatives.search(for: session, calendarAccess: true,
            events: changed, data: data, now: now, preparationIncluded: true))
        XCTAssertTrue(data.moves.isEmpty)
    }

    func testLocalCorrectionParsesOnlyOneExplicitOrdinalAndDay() throws {
        XCTAssertEqual(try CoachPlanningRefinement.parse("sposta il secondo a venerdì", count: 3), .init(index: 1, weekday: 6))
        for text in ["sposta quello a venerdì", "sposta il secondo a venerdì e il primo a sabato", "non sposta il secondo a venerdì", "sposta il terzo a venerdì"] {
            XCTAssertThrowsError(try CoachPlanningRefinement.parse(text, count: 2))
        }
    }

    func testCorrectionMovesOnlySecondActivityAndPreservesFirstAndExclusions() throws {
        let (session, events, data) = try fixture(count: 2)
        let original = try XCTUnwrap(options(session, events, data).first)
        let revised = try CoachPlanningRefinement.apply(.init(index: 1, weekday: 6), to: original,
            session: session, events: events, data: data, calendarAccess: true, now: now)
        XCTAssertEqual(revised.moves[0].proposedStart, original.moves[0].proposedStart)
        XCTAssertEqual(revised.moves[0].proposedEnd, original.moves[0].proposedEnd)
        XCTAssertEqual(PivotDate.calendar.component(.weekday, from: revised.moves[1].proposedStart), 6)
        XCTAssertNil(CoachPlanner.validate(revised, events: events, data: data, now: now))
        XCTAssertEqual(session.intent.excludedDayOffsets, [2])
        XCTAssertTrue(data.moves.isEmpty)
    }

    func testCorrectionCannotReadmitExcludedDayOrSilentlyInvertOrder() throws {
        let (session, events, data) = try fixture(count: 2)
        let original = try XCTUnwrap(options(session, events, data).first)
        for request in [CoachPlanningRefinement.Request(index: 1, weekday: 4), .init(index: 0, weekday: 6)] {
            XCTAssertThrowsError(try CoachPlanningRefinement.apply(request, to: original,
                session: session, events: events, data: data, calendarAccess: true, now: now))
        }
        XCTAssertTrue(data.moves.isEmpty)
    }

    func testCorrectionRejectsExpiredAlternativeAndChangedSource() throws {
        let (session, events, data) = try fixture(count: 2)
        let original = try XCTUnwrap(options(session, events, data).first)
        XCTAssertThrowsError(try CoachPlanningRefinement.apply(.init(index: 1, weekday: 6), to: original,
            session: session, events: events, data: data, calendarAccess: true, now: now.addingTimeInterval(121)))
        var changed = events; changed[0].location = "Luogo QA modificato"
        XCTAssertThrowsError(try CoachPlanningRefinement.apply(.init(index: 1, weekday: 6), to: original,
            session: session, events: changed, data: data, calendarAccess: true, now: now))
    }
}
