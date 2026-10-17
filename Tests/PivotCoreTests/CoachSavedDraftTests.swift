import XCTest
@testable import PivotCore

final class CoachSavedDraftTests: XCTestCase {
    private func fixture() -> AppData {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let message = CoachMessage(dayKey: PivotDate.key(now), role: .coach, text: "Bozza pronta", onlineHistoryEligible: true)
        let draft = CoachCalendarDraft(title: "Prova sintetica", start: now, end: now.addingTimeInterval(3600), calendarHint: nil, notes: "Note sintetiche solo telefono", endEstimated: false)
        let saved = CoachSavedCalendarDraft(messageID: message.id, dayKey: message.dayKey, draft: draft, calendarID: "calendar-id-qa")
        var data = AppData(); data.coach = CoachState(messages: [message], calendarDrafts: [saved]); return data
    }
    func testPendingDraftSurvivesBackupWithStableCardAndMessageIDs() throws {
        let data = fixture(), original = data.coachState.calendarDrafts![0]
        let restored = try BackupCodec.decode(BackupCodec.encodeCompact(data))
        let saved = try XCTUnwrap(restored.coachState.calendarDrafts?.first)
        XCTAssertEqual(saved.id, original.id); XCTAssertEqual(saved.messageID, original.messageID)
        XCTAssertEqual(saved.draft.title, original.draft.title); XCTAssertEqual(saved.draft.notes, original.draft.notes)
        XCTAssertEqual(saved.calendarID, "calendar-id-qa"); XCTAssertNil(saved.createdEventID)
    }
    func testReopeningAndEditingUpdatesSameDraftWithoutAnyIncomeOrMove() throws {
        var data = fixture(); let saved = data.coachState.calendarDrafts![0]
        var edited = saved.draft; edited.title = "Titolo corretto"; edited.notes = "Note corrette"
        XCTAssertTrue(CoachDraftStore.update(id: saved.id, draft: edited, calendarID: "calendar-id-other-qa", data: &data))
        XCTAssertEqual(data.coachState.calendarDrafts?.count, 1)
        XCTAssertEqual(data.coachState.calendarDrafts?[0].draft.title, edited.title)
        XCTAssertTrue(data.income.isEmpty); XCTAssertTrue(data.payments.isEmpty); XCTAssertTrue(data.moves.isEmpty)
        XCTAssertNoThrow(try BackupCodec.decode(BackupCodec.encodeCompact(data)))
    }
    func testIncompleteOrInvalidTimesStayEditableButCannotPassCreationGate() throws {
        var data = fixture(); let saved = data.coachState.calendarDrafts![0]
        var edited = saved.draft; edited.title = ""; edited.end = edited.start?.addingTimeInterval(-60)
        XCTAssertTrue(CoachDraftStore.update(id: saved.id, draft: edited, calendarID: nil, data: &data))
        XCTAssertNoThrow(try BackupCodec.decode(BackupCodec.encodeCompact(data)))
        XCTAssertNotNil(data.coachState.calendarDrafts?[0].draft.problem(now: Date(), calendarID: "qa"))
    }
    func testCreatedDraftCannotBeEditedOrMarkedAsDifferentEvent() {
        var data = fixture(); let saved = data.coachState.calendarDrafts![0]
        XCTAssertTrue(CoachDraftStore.markCreated(id: saved.id, eventID: "event-qa", calendarID: "calendar-id-qa", data: &data))
        XCTAssertTrue(CoachDraftStore.markCreated(id: saved.id, eventID: "event-qa", calendarID: "calendar-id-qa", data: &data))
        XCTAssertFalse(CoachDraftStore.markCreated(id: saved.id, eventID: "other-event-qa", calendarID: "calendar-id-qa", data: &data))
        XCTAssertFalse(CoachDraftStore.update(id: saved.id, draft: saved.draft, calendarID: nil, data: &data))
        XCTAssertEqual(data.coachState.calendarDrafts?.count, 1)
    }
    func testOrphanedOrDuplicateCardsAreRejected() throws {
        var data = fixture(); let saved = data.coachState.calendarDrafts![0]
        data.coach?.messages = []
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encodeCompact(data)))
        data = fixture(); let duplicate = data.coachState.calendarDrafts![0]; data.coach?.calendarDrafts?.append(duplicate)
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encodeCompact(data)))
        data = fixture(); data.coach?.calendarDrafts?[0].messageID = saved.messageID
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encodeCompact(data)))
    }
    func testOversizedEditIsRejectedWithoutLosingOriginalDraft() {
        var data = fixture(); let saved = data.coachState.calendarDrafts![0]
        var edited = saved.draft; edited.notes = String(repeating: "a", count: 3001)
        XCTAssertFalse(CoachDraftStore.update(id: saved.id, draft: edited, calendarID: nil, data: &data))
        XCTAssertEqual(data.coachState.calendarDrafts?[0].draft.notes, saved.draft.notes)
    }
    func testDraftNotesAndCalendarIDsDoNotEnterCloudContextAutomatically() throws {
        let data = fixture()
        let snapshot = try CoachV8Snapshot.make(message: "Organizza la giornata", events: [], data: data, now: Date(), purpose: "conversation")
        let sent = String(decoding: snapshot.encodedRequest, as: UTF8.self)
        XCTAssertFalse(sent.contains("Note sintetiche solo telefono")); XCTAssertFalse(sent.contains("calendar-id-qa"))
    }
    func testLegacyCoachWithoutDraftsDecodes() throws {
        var data = AppData(); data.coach = CoachState()
        XCTAssertNil(try BackupCodec.decode(BackupCodec.encodeCompact(data)).coachState.calendarDrafts)
    }
}
