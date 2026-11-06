import XCTest
@testable import PivotCore

final class CoachPlanningLogisticsTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-19T12:00:00+02:00")!
    private func fixture(count: Int = 1) throws -> (CoachPlanningSession, [CalendarItem], AppData) {
        var data = AppData(); data.updatedAt = now
        data.settings.quietEndHour = 8; data.settings.quietStartHour = 22
        var sources: [CalendarItem] = [], events: [CalendarItem] = []
        for index in 0..<count {
            let start = now.addingTimeInterval(-Double(index + 1) * 7200)
            let source = CalendarItem(id: "group-main-\(index)-qa", eventIdentifier: "native-main-\(index)-qa",
                calendarIdentifier: "qa", calendarTitle: "QA", title: "Allenamento QA \(index)",
                start: start, end: start.addingTimeInterval(3600), location: "Destinazione QA", notes: "", colorHex: "7EE6CD",
                isAllDay: false, writable: true, kind: .workout, sourceIdentifier: "source-qa", recurring: false)
            var trip = source; trip.id = "group-trip-\(index)-qa"; trip.eventIdentifier = "native-trip-\(index)-qa"
            trip.title = "Viaggio QA \(index)"; trip.start = start.addingTimeInterval(-1200); trip.end = start; trip.kind = .other
            var options = CalendarCreationOptions(); options.location = source.location
            options.travel = .init(minutes: 20, origin: "Origine QA")
            XCTAssertTrue(CalendarActivityLinks.capture(id: UUID(), receipt: .init(activity: source, travel: trip),
                options: options, data: &data, now: now))
            data.rules[source.id] = .init(flexibility: .movable, minimumMinutes: 60,
                travelBeforeMinutes: 10, travelAfterMinutes: 15, travelConfirmed: true)
            sources.append(source); events += [source, trip]
        }
        let snapshot = try CoachV8Snapshot.make(message: "Recupero gruppi QA", events: events, data: data, now: now,
            purpose: "conversation", protocolVersion: 4, calendarScope: .week)
        let aliases = try sources.map { source in try XCTUnwrap(snapshot.sources.first { $0.value.id == source.id }?.key) }
        let intent = CoachPlanningIntent(eventIDs: aliases, allowedDayOffsets: [1, 3, 4], excludedDayOffsets: [2],
            band: .afternoon, earliestMinute: nil, latestMinute: nil, afterEventID: nil)
        let response = CoachV8Response(version: 4, requestID: snapshot.request.requestID, mode: .recover,
            eventIDs: [], reply: "QA", actions: [], planning: intent)
        let session = try CoachPlanningSession.make(response, snapshot: snapshot, messageID: UUID(), userMessageID: UUID(),
            access: .init(calendar: true, online: true), events: events, data: data, now: now)
        data.coachState.messages = [
            .init(id: session.userMessageID, dayKey: session.dayKey, role: .user, text: "QA", onlineHistoryEligible: true),
            .init(id: session.messageID, dayKey: session.dayKey, role: .coach, text: "QA")
        ]
        try CoachPlanningStore.save(session, in: &data.coachState)
        return (session, events, data)
    }
    private func search(_ session: CoachPlanningSession, _ events: [CalendarItem], _ data: AppData) throws -> [CoachOption] {
        try CoachPlanningAlternatives.options(for: session, calendarAccess: true, events: events, data: data,
            now: now, preparationIncluded: true)
    }
    func testJointGroupsKeepOutboundReturnOrderAndDurationsWithoutWrites() throws {
        let (session, events, data) = try fixture(count: 2)
        let options = try search(session, events, data)
        XCTAssertFalse(options.isEmpty)
        for option in options {
            XCTAssertEqual(option.moves.count, 2)
            XCTAssertNil(CoachPlanningLogistics.validate(option, session: session, events: events, data: data, now: now))
            XCTAssertNotNil(CoachPlanner.validate(option, events: events, data: data, now: now), "Single-move protection remains intact")
            for move in option.moves {
                let trip = try XCTUnwrap(CoachPlanningLogistics.tripMove(for: move, session: session))
                XCTAssertEqual(trip.proposedEnd, move.proposedStart)
                XCTAssertEqual(trip.proposedEnd.timeIntervalSince(trip.proposedStart), 1200)
                XCTAssertEqual(move.proposedEnd.timeIntervalSince(move.proposedStart), 3600)
            }
            let secondTrip = try XCTUnwrap(CoachPlanningLogistics.tripMove(for: option.moves[1], session: session))
            XCTAssertGreaterThanOrEqual(secondTrip.proposedStart.timeIntervalSince(option.moves[0].proposedEnd), 15 * 60)
        }
        XCTAssertTrue(data.moves.isEmpty); XCTAssertTrue(data.coachState.pendingCalendarChanges.isEmpty)
        XCTAssertNil(data.coachState.calendarBatches)
    }
    func testLinkedJourneyCountsOnceInBudgetAndDefaultJourneyIsNotAnotherDestination() throws {
        let (session, events, data) = try fixture()
        let source = try XCTUnwrap(session.groupSnapshots?.first?.activity)
        let budget = try CoachPlanningLogistics.budget(source, session: session, data: data)
        XCTAssertEqual(budget.beforeMinutes, 20); XCTAssertEqual(budget.occupiedMinutes, 95)
        let trip = try XCTUnwrap(session.groupSnapshots?.first?.travel)
        let available = CoachPlanningLogistics.availabilityData(events: events, data: data)
        XCTAssertTrue(EventRule.effective(for: trip, data: available).travelConfirmed)
        XCTAssertNil(data.rules[trip.id], "Availability copy cannot change saved rules")
    }
    func testExplicitUnconfirmedJourneyRuleIsNeverOverridden() throws {
        let (session, events, initial) = try fixture()
        let trip = try XCTUnwrap(session.groupSnapshots?.first?.travel)
        var data = initial
        data.rules[trip.id] = .init(flexibility: .fixed, minimumMinutes: 20, travelConfirmed: false)
        let available = CoachPlanningLogistics.availabilityData(events: events, data: data)
        XCTAssertFalse(EventRule.effective(for: trip, data: available).travelConfirmed)
    }
    func testChangingOnlyTripOrDeletingOneMemberInvalidatesTheWholePlan() throws {
        let (session, events, data) = try fixture()
        var changed = events; changed[1].start.addTimeInterval(-60)
        for list in [changed, [events[0]], events + [events[1]]] {
            XCTAssertThrowsError(try search(session, list, data))
        }
        XCTAssertTrue(data.moves.isEmpty)
    }
    func testCapturedGroupsSurviveBackupAndStayOutOfProviderPayloads() throws {
        let (session, events, data) = try fixture()
        let restored = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertEqual(restored.coachState.planningSessions?.first?.groupSnapshots, session.groupSnapshots)
        let snapshot = try CoachV8Snapshot.make(message: "Continua il piano QA", events: events, data: data, now: now,
            purpose: "conversation", protocolVersion: 4, calendarScope: .week)
        let raw = String(decoding: snapshot.encodedRequest, as: UTF8.self)
        for secret in ["groupSnapshots", "durationChoices", "Origine QA", "native-trip-0-qa", "native-main-0-qa"] {
            XCTAssertFalse(raw.contains(secret))
        }
    }
    func testLegacyPlanRequiresExplicitGroupReviewInsteadOfMovingHalfPair() throws {
        let (saved, events, initial) = try fixture()
        var legacy = saved; legacy.groupSnapshots = nil
        var data = initial; try CoachPlanningStore.save(legacy, in: &data.coachState)
        XCTAssertThrowsError(try search(legacy, events, data))
        legacy.groupSnapshots = try CoachPlanningLogistics.capture(sources: [events[0]], events: events, data: data)
        try CoachPlanningStore.save(legacy, in: &data.coachState)
        XCTAssertFalse(try search(legacy, events, data).isEmpty)
        XCTAssertTrue(data.moves.isEmpty)
    }
    func testStageCreatesReviewBatchAndExistingExpanderIncludesBothMembers() throws {
        let (session, events, initial) = try fixture()
        let option = try XCTUnwrap(search(session, events, initial).first)
        var data = initial
        try CoachPlanningAlternatives.stage(option, session: session, calendarAccess: true, events: events, data: &data,
            now: now, preparationIncluded: true, routesReviewed: true)
        let batch = try XCTUnwrap(data.coachState.calendarBatches?.first)
        XCTAssertEqual(batch.actions.count, 1, "The established final review expands the linked trip")
        let expanded = try CalendarActivityLinks.expanded(batch.actions, data: data, choices: [:], now: now, mapsConsent: false)
        XCTAssertEqual(expanded.count, 2)
        XCTAssertEqual(Set(expanded.map { $0.source.id }), Set(events.map(\.id)))
        XCTAssertTrue(data.moves.isEmpty); XCTAssertTrue(data.coachState.pendingCalendarChanges.isEmpty)
        XCTAssertEqual(data.coachState.planningSessions?.first?.status, .staged)
        XCTAssertTrue(data.income.isEmpty); XCTAssertTrue(data.payments.isEmpty)
        XCTAssertNoThrow(try BackupCodec.decode(BackupCodec.encode(data)))
    }
    func testStaleStageIsAtomicForChangedTripAndMissingRouteReview() throws {
        let (session, events, initial) = try fixture()
        let option = try XCTUnwrap(search(session, events, initial).first)
        for scenario in 0..<3 {
            var data = initial, changed = events
            if scenario == 0 { changed[1].notes = "Modifica esterna QA" }
            XCTAssertThrowsError(try CoachPlanningAlternatives.stage(option, session: session, calendarAccess: true,
                events: changed, data: &data, now: now.addingTimeInterval(scenario == 2 ? 121 : 0),
                preparationIncluded: true, routesReviewed: scenario != 1))
            XCTAssertNil(data.coachState.calendarBatches); XCTAssertTrue(data.moves.isEmpty)
            XCTAssertEqual(data.coachState.planningSessions, initial.coachState.planningSessions)
        }
    }
    func testRemovedOrChangedNativeLinkCannotBeSilentlyAdopted() throws {
        let (session, events, initial) = try fixture()
        var data = initial; data.calendarActivityLinks?[0].deleted = true
        XCTAssertThrowsError(try search(session, events, data))
        data = initial; data.calendarActivityLinks?[0].settings.origin = "Altra origine QA"
        XCTAssertThrowsError(try search(session, events, data))
    }
    func testBusyOutboundTimeBlocksOtherwiseFreeActivityStart() throws {
        let (session, events, initial) = try fixture()
        let original = try XCTUnwrap(search(session, events, initial).first?.moves.first)
        let trip = try XCTUnwrap(CoachPlanningLogistics.tripMove(for: original, session: session))
        var block = events[0]; block.id = "outbound-block-qa"; block.eventIdentifier = "native-block-qa"
        block.start = trip.proposedStart; block.end = trip.proposedEnd; block.location = ""
        var data = initial; data.rules[block.id] = .init(flexibility: .fixed, minimumMinutes: 20, travelConfirmed: true)
        let alternatives = try search(session, events + [block], data)
        XCTAssertFalse(alternatives.isEmpty)
        for option in alternatives {
            let moved = try XCTUnwrap(option.moves.first)
            let outbound = try XCTUnwrap(CoachPlanningLogistics.tripMove(for: moved, session: session))
            XCTAssertFalse(outbound.proposedStart < block.end && outbound.proposedEnd > block.start)
        }
    }
    func testSavedPinsAndCorrectionApplyToWholeGroupWithoutCalendarWrites() throws {
        let (session, events, initial) = try fixture(count: 2)
        let original = try XCTUnwrap(search(session, events, initial).first)
        let revision = try CoachPlanningRefinement.revise(.init(index: 1, weekday: 6, minute: 990), option: original,
            session: session, events: events, data: initial, calendarAccess: true, now: now)
        XCTAssertEqual(revision.option.moves[0].proposedStart, original.moves[0].proposedStart)
        XCTAssertEqual(PivotDate.time(revision.option.moves[1].proposedStart), "16:30")
        let trip = try XCTUnwrap(CoachPlanningLogistics.tripMove(for: revision.option.moves[1], session: revision.session))
        XCTAssertEqual(PivotDate.time(trip.proposedStart), "16:10")
        var data = initial; try CoachPlanningStore.save(revision.session, in: &data.coachState)
        XCTAssertFalse(try search(revision.session, events, data).isEmpty)
        XCTAssertTrue(data.moves.isEmpty)
    }
    func testMalformedGroupBackupAndRaisedMinimumAreRejected() throws {
        let (session, events, initial) = try fixture()
        var data = initial; data.coachState.planningSessions?[0].groupSnapshots?.append(session.groupSnapshots![0])
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(data)))
        data = initial; data.rules[events[0].id]?.minimumMinutes = 90
        XCTAssertThrowsError(try search(session, events, data))
    }
private func withDuration(_ session: CoachPlanningSession, _ events: [CalendarItem], _ initial: AppData) throws -> (CoachPlanningSession, AppData) {
        let plan = TrainingPlan(payload: .init(formatVersion: 1, name: "Scheda durata QA", days: [
            .init(id: "day-qa", name: "Giorno QA", exercises: [.init(id: "exercise-qa", name: "Esercizio QA", sets: 1, reps: "6", restSeconds: 60, coachNotes: "")])]))
        var library = TrainingLibrary(plans: [plan])
        for (index, minutes) in [60, 75, 90].enumerated() {
            var sample = library.makeSession(plan: plan, day: plan.payload.days[0], eventID: nil, now: now.addingTimeInterval(-Double(index + 1) * 86400))
            sample.end = sample.start.addingTimeInterval(Double(minutes) * 60)
            sample.exercises[0].sets[0].kg = 20; sample.exercises[0].sets[0].reps = 6; sample.exercises[0].sets[0].done = true
            library.sessions.append(sample)
        }
        var data = initial; data.training = library
        var next = session
        next.durationChoices = [try CoachPlanningDurationChoice.make(source: events[0], planID: plan.id, dayID: "day-qa", library: library, now: now)]
        try CoachPlanningStore.save(next, in: &data.coachState)
        return (next, data)
    }
    func testAdoptedDurationExtendsGroupAndStagesBothWithoutChangingHistory() throws {
        let (initialSession, events, initialData) = try fixture()
        let (session, initial) = try withDuration(initialSession, events, initialData)
        let option = try XCTUnwrap(search(session, events, initial).first)
        XCTAssertEqual(option.moves[0].proposedEnd.timeIntervalSince(option.moves[0].proposedStart), 75 * 60)
        var data = initial
        try CoachPlanningAlternatives.stage(option, session: session, calendarAccess: true, events: events, data: &data,
            now: now, preparationIncluded: true, routesReviewed: true)
        let batch = try XCTUnwrap(data.coachState.calendarBatches?.first)
        let expanded = try CalendarActivityLinks.expanded(batch.actions, data: data, choices: [:], now: now, mapsConsent: false)
        XCTAssertEqual(expanded.count, 2)
        XCTAssertEqual(data.training?.sessions, initial.training?.sessions)
        XCTAssertTrue(data.moves.isEmpty); XCTAssertTrue(data.payments.isEmpty)
    }
    func testDurationChoiceSurvivesBackupAndIsNeverSentToProvider() throws {
        let (initialSession, events, initialData) = try fixture()
        let (session, data) = try withDuration(initialSession, events, initialData)
        let restored = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertEqual(restored.coachState.planningSessions?.first?.durationChoices, session.durationChoices)
        let snapshot = try CoachV8Snapshot.make(message: "Continua QA", events: events, data: data, now: now,
            purpose: "conversation", protocolVersion: 4, calendarScope: .week)
        let raw = String(decoding: snapshot.encodedRequest, as: UTF8.self)
        for forbidden in ["durationChoices", "sampleMinutes", "Scheda durata QA", data.training!.plans[0].id.uuidString] {
            XCTAssertFalse(raw.contains(forbidden))
        }
    }
    func testForgedShorterDurationOrChangedLibraryCannotBeUsedForSearchOrStaging() throws {
        let (initialSession, events, initialData) = try fixture()
        let (session, initial) = try withDuration(initialSession, events, initialData)
        var bad = initial; bad.coachState.planningSessions?[0].durationChoices?[0].activityMinutes = 30
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(bad)))
        let option = try XCTUnwrap(search(session, events, initial).first)
        var changed = initial
        changed.training?.plans[0].payload.days[0].exercises[0].restSeconds = 120
        XCTAssertThrowsError(try search(session, events, changed))
        XCTAssertThrowsError(try CoachPlanningAlternatives.stage(option, session: session, calendarAccess: true,
            events: events, data: &changed, now: now, preparationIncluded: true, routesReviewed: true))
        XCTAssertTrue(changed.moves.isEmpty); XCTAssertNil(changed.coachState.calendarBatches)
    }
func testNativeIndexKeepsAmbiguousIdentitiesInsteadOfChoosingTheFirst() throws {
        let (_, events, data) = try fixture()
        let expected = events[0]
        let index = CoachPlanningLogistics.EventIndex([expected, expected])
        XCTAssertEqual(index.matches(expected).count, 2)
        let crowded = CoachPlanningLogistics.EventIndex(Array(repeating: expected, count: 9))
        XCTAssertTrue(crowded.matches(expected).isEmpty)
        let available = CoachPlanningLogistics.availabilityData(events: events + [events[1]], data: data)
        XCTAssertNil(available.rules[events[1].id])
    }
    func testNativeIndexRespectsAccountAndDoesNotUseSameTitleAsIdentity() throws {
        let (_, events, _) = try fixture()
        let expected = events[0]
        var other = expected; other.eventIdentifier = "different-native-qa"; other.id = "different-local-qa"
        var account = expected; account.sourceIdentifier = "other-account-qa"
        let index = CoachPlanningLogistics.EventIndex([other, account])
        XCTAssertTrue(index.matches(expected).isEmpty)
    }
}
