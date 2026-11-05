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
func testNaturalCorrectionsResolveExactTitlesClockAndExplicitUnchangedActivity() throws {
        var sources = try fixture(count: 2).1
        sources[0].title = "Bench"; sources[1].title = "Stacco rumeno"
        XCTAssertEqual(try CoachPlanningRefinement.parse("Metti STACCO RUMENO a venerdì alle 16:30, lascia fermo il primo.", sources: sources),
                       .init(index: 1, weekday: 6, minute: 990))
        XCTAssertEqual(try CoachPlanningRefinement.parse("il secondo meglio venerdì", sources: sources), .init(index: 1, weekday: 6))
        XCTAssertEqual(try CoachPlanningRefinement.parse("sposta Bench al martedì alle 15", sources: sources),
                       .init(index: 0, weekday: 3, minute: 900))
    }

    func testAmbiguousTitlesNegationContradictionsAndInvalidClocksDoNotGuess() throws {
        var sources = try fixture(count: 2).1
        sources[0].title = "Bench"; sources[1].title = "Bench"
        for text in ["sposta Bench a venerdì", "non sposta il secondo a venerdì",
                     "sposta il secondo a venerdì se posso", "sposta il secondo a venerdì alle 24:00",
                     "sposta il secondo a venerdì alle 16:60", "sposta il secondo a venerdì alle 16:3",
                     "sposta il secondo a venerdì, lascia fermo il secondo",
                     "sposta il secondo a venerdì e il primo a sabato"] {
            XCTAssertThrowsError(try CoachPlanningRefinement.parse(text, sources: sources), text)
        }
        XCTAssertThrowsError(try CoachPlanningRefinement.parse("sposta il primo a venerdì", count: Int.max))
        XCTAssertThrowsError(try CoachPlanningRefinement.parse("sposta il primo a venerdì", count: -1))
    }

    private func corrected(_ session: CoachPlanningSession, _ events: [CalendarItem], _ data: AppData,
                           minute: Int? = nil) throws -> CoachPlanningRefinement.Revision {
        let original = try XCTUnwrap(options(session, events, data).first)
        return try CoachPlanningRefinement.revise(.init(index: 1, weekday: 6, minute: minute), option: original,
            session: session, events: events, data: data, calendarAccess: true, now: now)
    }

    func testExactClockCorrectionPreservesOtherStartFullDurationAndTravelBudget() throws {
        let (session, events, data) = try fixture(count: 2, seconds: 3601)
        let original = try XCTUnwrap(options(session, events, data).first)
        let revision = try corrected(session, events, data, minute: 990)
        XCTAssertEqual(revision.option.moves[0].proposedStart, original.moves[0].proposedStart)
        XCTAssertEqual(PivotDate.time(revision.option.moves[1].proposedStart), "16:30")
        XCTAssertEqual(revision.option.moves[1].proposedEnd.timeIntervalSince(revision.option.moves[1].proposedStart), 3601)
        XCTAssertEqual(revision.session.localPins?.count, 2)
        XCTAssertTrue(CoachPlanningAlternatives.matchesPins(revision.option, session: revision.session))
        XCTAssertNil(CoachPlanner.validate(revision.option, events: events, data: data, now: now))
        XCTAssertNil(session.localPins); XCTAssertTrue(data.moves.isEmpty)
    }

    func testCorrectionPinsSurviveBackupAndReopeningWithoutBecomingCalendarMoves() throws {
        let (session, events, initial) = try fixture(count: 2)
        let revision = try corrected(session, events, initial, minute: 990)
        var data = initial
        try CoachPlanningStore.save(revision.session, in: &data.coachState)
        let restored = try BackupCodec.decode(BackupCodec.encode(data))
        let saved = try XCTUnwrap(restored.coachState.planningSessions?.first)
        XCTAssertEqual(saved.localPins, revision.session.localPins)
        let reopened = try XCTUnwrap(options(saved, events, restored, at: now.addingTimeInterval(121)).first)
        XCTAssertEqual(reopened.moves.map(\.proposedStart), revision.option.moves.map(\.proposedStart))
        XCTAssertTrue(restored.moves.isEmpty); XCTAssertTrue(restored.coachState.pendingCalendarChanges.isEmpty)
        XCTAssertEqual(restored.income.count, initial.income.count); XCTAssertEqual(restored.payments.count, initial.payments.count)
    }

    func testDayOnlyChoiceKeepsAbsoluteFridayAcrossMidnight() throws {
        let (session, events, initial) = try fixture(count: 2)
        let revision = try corrected(session, events, initial)
        XCTAssertNil(revision.session.localPins?.last?.start)
        var data = initial
        try CoachPlanningStore.save(revision.session, in: &data.coachState)
        let tomorrow = now.addingTimeInterval(20 * 3600)
        for option in try options(revision.session, events, data, at: tomorrow) {
            XCTAssertEqual(PivotDate.calendar.startOfDay(for: option.moves[1].proposedStart),
                           revision.session.localPins?.last?.day)
            XCTAssertEqual(option.moves[0].proposedStart, revision.option.moves[0].proposedStart)
        }
        XCTAssertFalse(try options(revision.session, events, data, at: tomorrow).isEmpty)
    }

    func testChangedExternalBusyTimeDoesNotSilentlyMovePinnedActivities() throws {
        let (session, events, initial) = try fixture(count: 2)
        let revision = try corrected(session, events, initial, minute: 990)
        var data = initial
        try CoachPlanningStore.save(revision.session, in: &data.coachState)
        var blocker = events[0]
        blocker.id = "external-blocker-qa"; blocker.eventIdentifier = "native-blocker-qa"
        blocker.start = revision.option.moves[1].proposedStart; blocker.end = revision.option.moves[1].proposedEnd
        data.rules[blocker.id] = .init(flexibility: .fixed, minimumMinutes: 1, travelConfirmed: true)
        XCTAssertTrue(try options(revision.session, events + [blocker], data).isEmpty)
        XCTAssertEqual(data.coachState.planningSessions?.first?.localPins, revision.session.localPins)
        XCTAssertTrue(data.moves.isEmpty); XCTAssertTrue(data.coachState.pendingCalendarChanges.isEmpty)
    }

    func testStageCannotBypassSavedChoicesUsingAnotherStillFreshAlternative() throws {
        let (session, events, initial) = try fixture(count: 2)
        let original = try XCTUnwrap(options(session, events, initial).first)
        let revision = try corrected(session, events, initial, minute: 990)
        var data = initial
        try CoachPlanningStore.save(revision.session, in: &data.coachState)
        XCTAssertThrowsError(try CoachPlanningAlternatives.stage(original, session: revision.session, calendarAccess: true,
            events: events, data: &data, now: now, preparationIncluded: true, routesReviewed: true))
        XCTAssertTrue(data.moves.isEmpty)
        try CoachPlanningAlternatives.stage(revision.option, session: revision.session, calendarAccess: true,
            events: events, data: &data, now: now, preparationIncluded: true, routesReviewed: true)
        XCTAssertEqual(data.coachState.pendingCalendarChanges.count, 2)
        XCTAssertTrue(data.moves.allSatisfy { !$0.syncedToCalendar })
    }

    func testInvalidDuplicateUnknownOrMismatchedCivilDayPinsAreRejectedInBackups() throws {
        let (session, events, initial) = try fixture(count: 2)
        let revision = try corrected(session, events, initial, minute: 990)
        let pin = try XCTUnwrap(revision.session.localPins?.first)
        let nextDay = PivotDate.calendar.date(byAdding: .day, value: 1, to: pin.day)!
        for bad in [
            [pin, pin],
            [CoachPlanningPin(sourceID: "unknown-qa", day: pin.day, start: nil)],
            [CoachPlanningPin(sourceID: events[0].id, day: pin.day.addingTimeInterval(60), start: nil)],
            [CoachPlanningPin(sourceID: events[0].id, day: pin.day, start: nextDay)]
        ] {
            var data = initial
            data.coachState.planningSessions?[0].localPins = bad
            XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(data)))
        }
    }

    func testBackupWithoutNewOptionalPinsRemainsReadable() throws {
        let (_, _, data) = try fixture(count: 2)
        let decoded = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertNil(decoded.coachState.planningSessions?.first?.localPins)
        XCTAssertTrue(CoachPlanningStore.valid(decoded.coachState))
    }

    func testCloudContinuationPreservesLocalPinsButNeverEncodesThemInProviderContext() throws {
        let (session, events, initial) = try fixture(count: 2)
        let revision = try corrected(session, events, initial, minute: 990)
        var data = initial
        try CoachPlanningStore.save(revision.session, in: &data.coachState)
        let snap = try CoachV8Snapshot.make(message: "Continua il piano QA", events: events, data: data, now: now,
            purpose: "conversation", protocolVersion: 4, calendarScope: .week)
        let remapped = try XCTUnwrap(snap.request.planningContext?.first?.intent)
        let response = CoachV8Response(version: 4, requestID: snap.request.requestID, mode: .recover,
            eventIDs: [], reply: "QA", actions: [], planning: remapped)
        let continued = try CoachPlanningSession.make(response, snapshot: snap, messageID: UUID(), userMessageID: UUID(),
            access: .init(calendar: true, online: true), events: events, data: data, now: now)
        XCTAssertEqual(continued.id, revision.session.id)
        XCTAssertEqual(continued.localPins, revision.session.localPins)
        let raw = String(decoding: snap.encodedRequest, as: UTF8.self)
        XCTAssertFalse(raw.contains("localPins"))
        for event in events { XCTAssertFalse(raw.contains(event.id)) }
    }

    func testExpiredOrIncompatibleSavedChoicesRequireExplicitReview() throws {
        let (session, events, initial) = try fixture(count: 2)
        let revision = try corrected(session, events, initial, minute: 990)
        var changed = revision.session
        changed.intent.allowedDayOffsets = [1, 3]
        var data = initial
        try CoachPlanningStore.save(changed, in: &data.coachState)
        XCTAssertThrowsError(try options(changed, events, data))
        XCTAssertEqual(data.coachState.planningSessions?.first?.localPins, revision.session.localPins)
        data = initial
        try CoachPlanningStore.save(revision.session, in: &data.coachState)
        XCTAssertThrowsError(try options(revision.session, events, data, at: now.addingTimeInterval(2 * 86400)))
        XCTAssertTrue(data.moves.isEmpty)
    }

    func testFailedOrCancelledCorrectionLeavesPreviouslySavedChoicesUntouched() throws {
        let (session, events, initial) = try fixture(count: 2)
        let revision = try corrected(session, events, initial, minute: 990)
        var data = initial
        try CoachPlanningStore.save(revision.session, in: &data.coachState)
        let before = data.coachState.planningSessions
        for minute in [0, 1439] {
            XCTAssertThrowsError(try CoachPlanningRefinement.revise(.init(index: 1, weekday: 6, minute: minute),
                option: revision.option, session: revision.session, events: events, data: data, calendarAccess: true, now: now))
        }
        XCTAssertThrowsError(try CoachPlanningRefinement.revise(.init(index: 1, weekday: 6),
            option: revision.option, session: revision.session, events: events, data: data,
            calendarAccess: true, now: now, isCancelled: { true })) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(data.coachState.planningSessions, before)
        XCTAssertTrue(data.moves.isEmpty)
    }
}
