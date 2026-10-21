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
        var data = linked(); data.calendarActivityLinks?[0].settings.estimate = estimate
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
}
