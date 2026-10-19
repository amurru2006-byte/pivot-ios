import XCTest
@testable import PivotCore

final class CoachCalendarMutationTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-18T22:00:00+02:00")!
    private func item() -> CalendarItem {
        .init(id: "logical-test", eventIdentifier: "native-test", calendarIdentifier: "calendar-test", calendarTitle: "Personale Test",
              title: "Attività sintetica", start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600),
              location: "Luogo locale riservato", notes: "Note locali riservate", colorHex: "123456", isAllDay: false, writable: true, kind: .other, recurring: false)
    }
    private func edit(_ kind: CalendarMutationKind = .delete, id: String = "e0") -> CoachCalendarEdit {
        .init(kind: kind, eventID: id, title: nil, start: nil, end: nil, notes: nil)
    }
    private func archive(_ source: CalendarItem) -> ArchivedCalendarMutation {
        .init(batchID: UUID(), actionID: UUID(), kind: .delete,
              original: .init(snapshot: source, originalNotes: source.notes, url: nil, timeZoneIdentifier: "Europe/Rome", availabilityRawValue: 0, alarms: []),
              preparedAt: now)
    }
    func testActionBatchIsOnlyPreviewAndRetainsPrivateOriginalLocally() throws {
        let original = item(), data = AppData(), messageID = UUID()
        let batch = try CoachCalendarBatch.make([edit()], sources: ["e0": original], messageID: messageID, now: now, data: data)
        XCTAssertEqual(batch.status, .pending); XCTAssertEqual(batch.actions[0].source, original)
        XCTAssertNil(batch.actions[0].after); XCTAssertTrue(data.income.isEmpty); XCTAssertNil(data.calendarActionArchive)
    }
    func testUpdatesPreserveFieldsAndEmptyNotesDifferFromNoPatch() throws {
        let original = item()
        var change = edit(.update); change.title = "Titolo aggiornato"
        var batch = try CoachCalendarBatch.make([change], sources: ["e0": original], messageID: UUID(), now: now, data: AppData())
        XCTAssertEqual(batch.actions[0].after?.notes, original.notes)
        XCTAssertEqual(batch.actions[0].after?.location, original.location)
        XCTAssertEqual(batch.actions[0].after?.start, original.start)
        change.notes = ""
        batch = try CoachCalendarBatch.make([change], sources: ["e0": original], messageID: UUID(), now: now, data: AppData())
        XCTAssertEqual(batch.actions[0].after?.notes, "")
    }
    func testUnknownDuplicateReadonlyRunningAndPendingMoveTargetsFailClosed() throws {
        let original = item()
        for edits in [[edit(id: "e99")], [edit(), edit()], [edit(.update)]] {
            XCTAssertThrowsError(try CoachCalendarBatch.make(edits, sources: ["e0": original], messageID: UUID(), now: now, data: AppData()))
        }
        var readOnly = original; readOnly.writable = false
        XCTAssertThrowsError(try CoachCalendarBatch.make([edit()], sources: ["e0": readOnly], messageID: UUID(), now: now, data: AppData()))
        var data = AppData(); data.records[original.id] = EventRecord(id: original.id, snapshot: original, status: .running)
        XCTAssertThrowsError(try CoachCalendarBatch.make([edit()], sources: ["e0": original], messageID: UUID(), now: now, data: data))
        data.records = [:]; data.moves = [PlanMove(source: original, proposedStart: now, proposedEnd: now.addingTimeInterval(3600))]
        XCTAssertThrowsError(try CoachCalendarBatch.make([edit()], sources: ["e0": original], messageID: UUID(), now: now, data: data))
    }
    func testArchiveNeedsConsistentOriginalAndDurableStateTransitions() throws {
        var value = archive(item()); XCTAssertTrue(value.isValid)
        value.original.originalNotes = "different"; XCTAssertFalse(value.isValid)
        value = archive(item()); value.status = .committed; XCTAssertFalse(value.isValid)
        value.committedAt = now; XCTAssertTrue(value.isValid)
        value.status = .restored; XCTAssertFalse(value.isValid)
        value.restoredAt = now; value.restoredEvent = item(); XCTAssertTrue(value.isValid)
        var data = AppData(); data.calendarActionArchive = [value]
        XCTAssertFalse(CalendarArchive.valid(data), "Deleted-event restoration requires its identity link")
    }
    func testRestoredLessonKeepsLogicalIdentityAndCannotBecomeAnotherReceipt() throws {
        var original = item(); original.kind = .tutoring
        var restored = original; restored.id = "new-logical-test"; restored.eventIdentifier = "new-native-test"
        var entry = archive(original); entry.status = .restored; entry.committedAt = now; entry.restoredAt = now; entry.restoredEvent = restored
        var data = AppData(); data.calendarActionArchive = [entry]
        data.calendarRestorations = [.init(archiveID: entry.id, original: original, restored: restored)]
        let client = Client(name: "Contatto Test", rateCents: 1000); data.clients = [client]
        data.income = [.init(clientID: client.id, clientName: client.name, date: original.end, minutes: 60,
                             amountCents: 1000, paidCents: 500, calendarEventID: original.id)]
        data.payments = [.init(incomeID: data.income[0].id, clientName: client.name, date: now, amountCents: 500)]
        XCTAssertTrue(CalendarArchive.valid(data))
        let current = try XCTUnwrap(EventCoalescer.unique([restored], data: data).first)
        XCTAssertEqual(current.id, original.id); XCTAssertEqual(current.eventIdentifier, restored.eventIdentifier)
        XCTAssertEqual(HistoricalIncome.existingEntry(for: current, data: data)?.id, data.income[0].id)
        XCTAssertThrowsError(try HistoricalIncome.quote(current, clientID: client.id, year: 2026, now: now, data: data))
        let decoded = try BackupCodec.decode(BackupCodec.encodeCompact(data))
        XCTAssertEqual(decoded.income[0].outstandingCents, 500); XCTAssertEqual(decoded.payments.count, 1)
        XCTAssertEqual(decoded.calendarRestorations?.count, 1)
    }
    func testOrphanMappingAndExternalURLCannotGrantRestorationIdentity() {
        let original = item(); var restored = original
        restored.id = "other-id"; restored.eventIdentifier = "other-native"
        var data = AppData(); data.calendarRestorations = [.init(archiveID: UUID(), original: original, restored: restored)]
        XCTAssertFalse(CalendarArchive.valid(data))
        XCTAssertEqual(CalendarArchive.logicalEvent(restored, data: data).id, restored.id)
    }
    func testInterruptedRestorationBlocksHistoricalImportUntilItsIdentityIsReconciled() throws {
        var source = item(); source.kind = .tutoring
        var entry = archive(source); entry.status = .restorationPrepared; entry.committedAt = now
        var data = AppData(); data.clients = [Client(name: "Contatto Test", rateCents: 1000)]
        data.calendarActionArchive = [entry]
        XCTAssertTrue(CalendarArchive.valid(data))
        XCTAssertThrowsError(try HistoricalIncome.quote(source, clientID: data.clients[0].id, year: 2026, now: now, data: data))
        XCTAssertTrue(data.income.isEmpty); XCTAssertTrue(data.payments.isEmpty)
    }
    func testBatchBackupRequiresConversationProvenanceAndDoesNotTouchFinance() throws {
        var data = AppData(); let message = CoachMessage(dayKey: PivotDate.key(now), role: .coach, text: "Proposta")
        let batch = try CoachCalendarBatch.make([edit()], sources: ["e0": item()], messageID: message.id, now: now, data: data)
        data.coachState.calendarBatches = [batch]
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encodeCompact(data)))
        data.coachState.messages = [message]
        XCTAssertNoThrow(try BackupCodec.decode(BackupCodec.encodeCompact(data)))
        XCTAssertTrue(data.income.isEmpty); XCTAssertTrue(data.payments.isEmpty)
    }
}
