import XCTest
@testable import PivotCore

final class CalendarActivityLinkTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let linkID = UUID(uuidString: "AAAA0000-0000-0000-0000-000000000001")!
    private var options: CalendarCreationOptions {
        var value = CalendarCreationOptions(); value.location = "Destinazione QA"
        value.travel = .init(minutes: 20, origin: "Partenza QA"); return value
    }
    private var draft: CoachCalendarDraft {
        .init(title: "Attività QA", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200),
              calendarHint: nil, notes: "Note QA", endEstimated: false)
    }
    private var receipt: CalendarCreationReceipt {
        let items = options.parts(draft: draft, creationID: linkID).map { part in
            CalendarItem(id: part.marker, eventIdentifier: part.marker, calendarIdentifier: "calendar-qa", calendarTitle: "QA",
                title: part.title, start: part.start, end: part.end, location: part.location, notes: part.notes,
                colorHex: "#00AA99", isAllDay: false, writable: true, kind: .other,
                sourceIdentifier: "source-qa", recurring: false)
        }
        return .init(activity: items[1], travel: items[0])
    }
    private func linked() -> AppData {
        var data = AppData()
        XCTAssertTrue(CalendarActivityLinks.capture(id: linkID, receipt: receipt, options: options, data: &data, now: now))
        return data
    }
    private func move() -> CoachCalendarMutation {
        var after = receipt.activity; after.start = after.start.addingTimeInterval(3600); after.end = after.end.addingTimeInterval(3600)
        return .init(kind: .update, source: receipt.activity, after: after)
    }
    private func expand(_ actions: [CoachCalendarMutation], data: AppData? = nil,
        choices: [String: CalendarCreationTravel] = [:], consent: Bool = false, at time: Date? = nil) throws -> [CoachCalendarMutation] {
        try CalendarActivityLinks.expanded(actions, data: data ?? linked(), choices: choices, now: time ?? now, mapsConsent: consent)
    }
    private func completed(_ actions: [CoachCalendarMutation]) -> [ArchivedCalendarMutation] {
        let batchID = UUID()
        return actions.map { action in
            let backup = CalendarEventBackup(snapshot: action.source, originalNotes: action.source.notes, url: nil,
                timeZoneIdentifier: nil, availabilityRawValue: 0, alarms: [])
            return .init(batchID: batchID, actionID: action.id, kind: action.kind, original: backup,
                after: action.after, status: .committed, preparedAt: now, committedAt: now)
        }
    }
    func testCaptureIsIdempotentAndPersistsIndependentlyOfConversation() throws {
        var data = linked()
        XCTAssertTrue(CalendarActivityLinks.capture(id: linkID, receipt: receipt, options: options, data: &data, now: now.addingTimeInterval(1)))
        XCTAssertEqual(data.calendarActivityLinks?.count, 1)
        data.coach = nil
        let restored = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertEqual(restored.calendarActivityLinks, data.calendarActivityLinks)
        XCTAssertTrue(restored.income.isEmpty); XCTAssertTrue(restored.payments.isEmpty)
    }
    func testCaptureRejectsCrossAccountWrongTimingAndSameNativeEvent() {
        var bad = receipt; bad.travel?.sourceIdentifier = "other-source"
        XCTAssertFalse(bad.isValid)
        bad = receipt; bad.travel?.end = now
        XCTAssertFalse(bad.isValid)
        bad = receipt; bad.travel?.eventIdentifier = bad.activity.eventIdentifier
        XCTAssertFalse(bad.isValid)
    }
    func testCaptureDoesNotAdoptChangedRetryOrSharedComponents() {
        var data = linked(); var changed = receipt; changed.activity.notes = "Altro QA"
        XCTAssertFalse(CalendarActivityLinks.capture(id: linkID, receipt: changed, options: options, data: &data, now: now))
        XCTAssertFalse(CalendarActivityLinks.capture(id: UUID(), receipt: receipt, options: options, data: &data, now: now))
        XCTAssertEqual(data.calendarActivityLinks?.count, 1)
    }
    func testDraftAcknowledgementAndLinkAreOneAtomicChange() {
        let message = CoachMessage(dayKey: PivotDate.key(now), role: .coach, text: "Bozza QA")
        let saved = CoachSavedCalendarDraft(id: linkID, messageID: message.id, dayKey: message.dayKey, draft: draft, calendarID: "calendar-qa")
        var data = AppData(); data.coach = CoachState(messages: [message], calendarDrafts: [saved])
        XCTAssertTrue(CoachDraftStore.completeCreation(id: linkID, receipt: receipt, options: options, data: &data, now: now))
        XCTAssertEqual(data.coachState.calendarDrafts?.first?.createdEventID, receipt.activity.id)
        XCTAssertEqual(data.calendarActivityLinks?.count, 1)
        var orphan = AppData()
        XCTAssertFalse(CoachDraftStore.completeCreation(id: linkID, receipt: receipt, options: options, data: &orphan, now: now))
        XCTAssertNil(orphan.calendarActivityLinks)
    }
    func testWrongReceiptCannotCompleteDraft() {
        let message = CoachMessage(dayKey: PivotDate.key(now), role: .coach, text: "Bozza QA")
        let saved = CoachSavedCalendarDraft(id: linkID, messageID: message.id, dayKey: message.dayKey, draft: draft, calendarID: "calendar-qa")
        var data = AppData(); data.coach = CoachState(messages: [message], calendarDrafts: [saved])
        var wrong = receipt; wrong.activity.title = "Non quella bozza"
        XCTAssertFalse(CoachDraftStore.completeCreation(id: linkID, receipt: wrong, options: options, data: &data, now: now))
        XCTAssertNil(data.calendarActivityLinks); XCTAssertNil(data.coachState.calendarDrafts?.first?.createdEventID)
    }
    func testMoveExpandsToJourneyAndRemainsIdempotentBeforeConfirmation() throws {
        let actions = try expand([move()])
        XCTAssertEqual(actions.count, 2)
        XCTAssertEqual(actions[1].after?.end, actions[0].after?.start)
        XCTAssertEqual(actions[1].after?.start, actions[0].after?.start.addingTimeInterval(-1200))
        XCTAssertEqual(try expand(actions), actions)
    }
    func testCancellationProposalIncludesJourneyAndRecordKeepsPrivateLink() throws {
        let actions = try expand([.init(kind: .delete, source: receipt.activity, after: nil)])
        XCTAssertEqual(actions.count, 2); XCTAssertTrue(actions.allSatisfy { $0.kind == .delete })
        var data = linked(); try CalendarActivityLinks.record(completed(actions), choices: [:], data: &data)
        XCTAssertEqual(data.calendarActivityLinks?.first?.deleted, true)
        XCTAssertNil(CalendarActivityLinks.link(for: receipt.activity, data: data))
    }
    func testApplyingOnlyOneHalfCannotBeAcknowledged() throws {
        var data = linked()
        XCTAssertThrowsError(try CalendarActivityLinks.record(completed([move()]), choices: [:], data: &data))
        XCTAssertEqual(data.calendarActivityLinks?.first?.activity, receipt.activity)
    }
    func testOpposingExplicitJourneyAndJourneyOnlyMutationAreRefused() {
        let wrong = CoachCalendarMutation(kind: .delete, source: receipt.travel!, after: nil)
        XCTAssertThrowsError(try expand([move(), wrong]))
        XCTAssertThrowsError(try expand([wrong]))
    }
    func testChangedActivityOrTripRevisionCannotBeSilentlyAdopted() {
        var action = move(); action.source.notes = "Modificato altrove"
        XCTAssertThrowsError(try expand([action]))
        var trip = receipt.travel!; trip.notes = "Modificato altrove"
        let changedTrip = CoachCalendarMutation(kind: .delete, source: trip, after: nil)
        XCTAssertThrowsError(try expand([.init(kind: .delete, source: receipt.activity, after: nil), changedTrip]))
    }
    func testUnlinkedSameTitleOrURLIsNeverPaired() throws {
        var action = move(); action.source.eventIdentifier = "untrusted-copy"
        action.source.id = "untrusted-copy"; action.after?.eventIdentifier = "untrusted-copy"; action.after?.id = "untrusted-copy"
        XCTAssertEqual(try expand([action]), [action])
    }
    func testManualAlternativeChangesJourneyWithoutRequestingMaps() throws {
        let choice = CalendarCreationTravel(minutes: 35, origin: "Altra partenza QA")
        let actions = try expand([move()], choices: [linkID.uuidString: choice])
        XCTAssertEqual(actions[1].after?.start, actions[0].after?.start.addingTimeInterval(-2100))
        var data = linked(); try CalendarActivityLinks.record(completed(actions), choices: [linkID.uuidString: choice], data: &data)
        XCTAssertEqual(data.calendarActivityLinks?.first?.settings, choice)
        XCTAssertEqual(data.calendarActivityLinks?.first?.activity.start, move().after?.start)
    }
    func testMapsJourneyRequiresFreshExplicitRouteAndConsent() throws {
        let action = move(), arrival = action.after!.start
        let request = TravelRouteRequest(origin: .init(name: "QA A", address: options.travel!.origin, latitude: 45, longitude: 9),
            destination: .init(name: "QA B", address: options.location, latitude: 45.1, longitude: 9.1), mode: .walking,
            timing: .arriveBy, date: arrival)
        let estimate = TravelEstimate(request: request, fetchedAt: now, departure: arrival.addingTimeInterval(-1800),
            arrival: arrival, travelSeconds: 1800, distanceMeters: 1000)
        let choice = CalendarCreationTravel(minutes: 30, origin: options.travel!.origin, estimate: estimate)
        var data = linked()
        var originalEstimate = estimate
        originalEstimate.request.date = receipt.activity.start
        originalEstimate.departure = receipt.travel!.start; originalEstimate.arrival = receipt.activity.start
        originalEstimate.travelSeconds = 1200
        data.calendarActivityLinks?[0].settings.estimate = originalEstimate
        XCTAssertThrowsError(try expand([action], data: data))
        XCTAssertThrowsError(try expand([action], data: data, choices: [linkID.uuidString: choice]))
        XCTAssertEqual(try expand([action], data: data, choices: [linkID.uuidString: choice], consent: true).count, 2)
        XCTAssertThrowsError(try expand([action], data: data, choices: [linkID.uuidString: choice], consent: true, at: now.addingTimeInterval(901)))
    }
    func testNotesOnlyChangeNeedsNoJourneyWrite() throws {
        var after = receipt.activity; after.notes = "Nuove note QA"
        let action = CoachCalendarMutation(kind: .update, source: receipt.activity, after: after)
        XCTAssertEqual(try expand([action]), [action])
        var data = linked(); try CalendarActivityLinks.record(completed([action]), choices: [:], data: &data)
        XCTAssertEqual(data.calendarActivityLinks?.first?.travel, receipt.travel)
    }
    func testMalformedBackupCannotInstallDuplicateNativeLinks() throws {
        var data = linked(); var duplicate = data.calendarActivityLinks![0]; duplicate.id = UUID()
        data.calendarActivityLinks?.append(duplicate)
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(data)))
        XCTAssertNoThrow(try BackupCodec.decode(BackupCodec.encode(AppData())))
    }
    func testUndoRequiresBothPartsOfTheSameBatchAndRestoresOriginalTravelSettings() throws {
        var data = linked()
        let choice = CalendarCreationTravel(minutes: 35, origin: "Altra partenza QA")
        let choices = [linkID.uuidString: choice]
        let actions = try expand([move()], choices: choices)
        var entries = CalendarActivityLinks.archiving(completed(actions), data: data)
        XCTAssertEqual(entries[0].linkedTravelBefore, options.travel)
        try CalendarActivityLinks.record(entries, choices: choices, data: &data)
        let moved = data.calendarActivityLinks
        entries[0].status = .restored; entries[0].restoredAt = now; entries[0].restoredEvent = entries[0].original.snapshot
        data.calendarActionArchive = entries
        CalendarActivityLinks.reconcileRestorations(data: &data)
        XCTAssertEqual(data.calendarActivityLinks, moved, "A half-restore must not silently redefine the pair")
        entries[1].status = .restored; entries[1].restoredAt = now; entries[1].restoredEvent = entries[1].original.snapshot
        data.calendarActionArchive = entries
        CalendarActivityLinks.reconcileRestorations(data: &data)
        XCTAssertEqual(data.calendarActivityLinks?.first?.activity, receipt.activity)
        XCTAssertEqual(data.calendarActivityLinks?.first?.travel, receipt.travel)
        XCTAssertEqual(data.calendarActivityLinks?.first?.settings, options.travel)
    }
    func testRestoredDeletionUsesAcknowledgedNewNativeIDsOnlyAfterBothPartsReturn() throws {
        var data = linked()
        let actions = try expand([.init(kind: .delete, source: receipt.activity, after: nil)])
        var entries = CalendarActivityLinks.archiving(completed(actions), data: data)
        try CalendarActivityLinks.record(entries, choices: [:], data: &data)
        for index in entries.indices {
            var restored = entries[index].original.snapshot
            restored.eventIdentifier = "restored-qa-\(index)"; restored.id = restored.eventIdentifier
            entries[index].status = .restored; entries[index].restoredAt = now; entries[index].restoredEvent = restored
        }
        var half = entries; half[1].status = .committed; half[1].restoredAt = nil; half[1].restoredEvent = nil
        data.calendarActionArchive = half; CalendarActivityLinks.reconcileRestorations(data: &data)
        XCTAssertEqual(data.calendarActivityLinks?.first?.deleted, true)
        data.calendarActionArchive = entries; CalendarActivityLinks.reconcileRestorations(data: &data)
        XCTAssertEqual(data.calendarActivityLinks?.first?.deleted, false)
        XCTAssertEqual(data.calendarActivityLinks?.first?.activity.eventIdentifier, "restored-qa-0")
        XCTAssertEqual(data.calendarActivityLinks?.first?.travel.eventIdentifier, "restored-qa-1")
        XCTAssertTrue(CalendarActivityLinks.valid(data))
    }
    func testAmbiguousRestoreBatchesCannotReestablishTheLink() throws {
        var data = linked(); let actions = try expand([move()])
        var entries = CalendarActivityLinks.archiving(completed(actions), data: data)
        try CalendarActivityLinks.record(entries, choices: [:], data: &data)
        for index in entries.indices {
            entries[index].status = .restored; entries[index].restoredAt = now; entries[index].restoredEvent = entries[index].original.snapshot
        }
        let otherID = UUID()
        let duplicate = entries.map { original -> ArchivedCalendarMutation in
            var copy = original; copy.batchID = otherID; copy.id = UUID(); copy.actionID = UUID(); return copy
        }
        let before = data.calendarActivityLinks
        data.calendarActionArchive = entries + duplicate
        CalendarActivityLinks.reconcileRestorations(data: &data)
        XCTAssertEqual(data.calendarActivityLinks, before)
    }
    func testLocalSingleEventPlannerCannotBypassPairedConfirmation() {
        let data = linked(), action = move()
        XCTAssertTrue(CalendarActivityLinks.requiresPairedReview(action.source, data: data))
        XCTAssertTrue(CalendarActivityLinks.requiresPairedReview(receipt.travel!, data: data))
        let plan = PlanMove(source: action.source, proposedStart: action.after!.start, proposedEnd: action.after!.end)
        let option = CoachOption(title: "QA", explanation: "QA", consequences: "QA", moves: [plan])
        XCTAssertTrue(CoachPlanner.validate(option, events: [receipt.activity, receipt.travel!], data: data, now: now)?.contains("viaggio collegato") == true)
    }
    func testLostAcknowledgementCannotAdvanceLinkUntilBothOutcomesAreVerified() throws {
        var data = linked()
        let choice = CalendarCreationTravel(minutes: 35, origin: "Nuova partenza QA")
        let choices = [linkID.uuidString: choice]
        let actions = try expand([move()], choices: choices)
        var entries = CalendarActivityLinks.archiving(completed(actions), data: data, choices: choices)
        entries[1].status = .uncertain
        data.calendarActionArchive = entries
        CalendarActivityLinks.reconcileAcknowledgements(data: &data)
        XCTAssertEqual(data.calendarActivityLinks?.first?.activity, receipt.activity)
        entries[1].status = .committed; data.calendarActionArchive = entries
        CalendarActivityLinks.reconcileAcknowledgements(data: &data)
        XCTAssertEqual(data.calendarActivityLinks?.first?.activity, actions[0].after)
        XCTAssertEqual(data.calendarActivityLinks?.first?.travel, actions[1].after)
        XCTAssertEqual(data.calendarActivityLinks?.first?.settings, choice)
        let before = data.calendarActivityLinks
        CalendarActivityLinks.reconcileAcknowledgements(data: &data)
        XCTAssertEqual(data.calendarActivityLinks, before)
    }
    func testLostDeletionAcknowledgementDoesNotReactivateOrRecreateAnything() throws {
        var data = linked()
        let actions = try expand([.init(kind: .delete, source: receipt.activity, after: nil)])
        data.calendarActionArchive = CalendarActivityLinks.archiving(completed(actions), data: data)
        CalendarActivityLinks.reconcileAcknowledgements(data: &data)
        XCTAssertEqual(data.calendarActivityLinks?.first?.deleted, true)
        XCTAssertTrue(data.moves.isEmpty); XCTAssertTrue(data.income.isEmpty)
    }
    func testBackupCannotSmuggleMismatchedDestinationDurationOrReadOnlyComponent() {
        var data = linked(); data.calendarActivityLinks?[0].travel.location = "Altra destinazione QA"
        XCTAssertFalse(CalendarActivityLinks.valid(data))
        data = linked(); data.calendarActivityLinks?[0].settings.minutes = 40
        XCTAssertFalse(CalendarActivityLinks.valid(data))
        data = linked(); data.calendarActivityLinks?[0].travel.writable = false
        XCTAssertFalse(CalendarActivityLinks.valid(data))
    }
}
