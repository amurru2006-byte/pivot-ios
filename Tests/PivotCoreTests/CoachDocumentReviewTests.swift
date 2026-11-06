import XCTest
@testable import PivotCore

final class CoachDocumentReviewTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let bytes = Data("%PDF-1.4\nSYNTHETIC REVIEW QA\n%%EOF".utf8)
    private func sample() throws -> (AppData, CoachDocumentReviewBatch) {
        var data = AppData()
        let source = CoachDocumentSource(document: .init(name: "Programma QA.pdf", byteCount: bytes.count), kind: .pdf,
            pageCount: 1, sha256: CoachDocumentSource.digest(bytes), importedAt: now)
        data.coachDocuments = [source]
        let packet = CoachDocumentPacket(createdAt: now, instruction: "Prepara due proposte QA", sources: [source],
            pages: [.init(sourceID: source.id, number: 1, text: "Prima esperienza 2030-01-14\nSeconda esperienza 2030-01-15", reading: .text)])
        _ = try CoachDocumentReviewStore.save(packet: packet, review: CoachDocumentLocalProposals.analyze(packet), data: &data, now: now)
        return (data, try XCTUnwrap(data.coachDocumentReviews?.first))
    }
    func testReadingAndCitationsRoundTripWithoutDuplicatingPDFsOrSendingMessages() throws {
        var (data, batch) = try sample(); data.studyPDFs = [batch.packet.sources[0].document.id.uuidString: bytes]
        let decoded = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertEqual(decoded.coachDocumentReviews, [batch]); XCTAssertEqual(decoded.studyPDFs?.count, 1)
        XCTAssertTrue(decoded.coachState.messages.isEmpty); XCTAssertNil(decoded.coachState.calendarDrafts)
        XCTAssertEqual(StudyFiles.documents(in: decoded).count, 1)
        let online = try CoachV8Snapshot.make(message: "Ciao", events: [], data: decoded, now: now, purpose: "conversation", protocolVersion: 3)
        let payload = String(decoding: online.encodedRequest, as: UTF8.self)
        XCTAssertFalse(payload.contains("Prima esperienza")); XCTAssertFalse(payload.contains("Programma QA.pdf"))
        XCTAssertFalse(payload.contains(batch.id.uuidString))
    }
    func testStagingSeveralAllDayDraftsKeepsReferencesAndNativeCreationUnconfirmed() throws {
        var (data, batch) = try sample()
        let ids = try CoachDocumentReviewStore.stage(batchID: batch.id, expected: batch, selected: batch.events.map(\.id), data: &data, now: now,
            nativeTimeZone: try XCTUnwrap(TimeZone(identifier: "Etc/UTC")))
        XCTAssertEqual(ids.count, 2); XCTAssertEqual(data.coachState.calendarDrafts?.count, 2)
        for saved in data.coachState.calendarDrafts ?? [] {
            XCTAssertNil(saved.calendarID); XCTAssertNil(saved.createdEventID)
            XCTAssertNotNil(saved.creationOptions?.allDay); XCTAssertNil(saved.creationOptions?.plannedTravel)
            XCTAssertFalse(saved.draft.endEstimated)
            XCTAssertTrue(saved.draft.notes.contains("pivot://document/")); XCTAssertEqual(saved.documentReferences?.first?.sourceID, batch.packet.sources[0].id)
        }
        XCTAssertTrue(data.coachState.messages.allSatisfy { $0.onlineHistoryEligible == false })
        XCTAssertNil(data.coachDocumentEventLinks); XCTAssertNil(data.calendarActivityLinks)
        XCTAssertTrue(CoachDraftStore.valid(data.coachState)); XCTAssertTrue(CoachDocumentLibrary.valid(data))
    }
    func testUnresolvedSelectionCannotPartiallyStageTheEarlierValidRow() throws {
        var (data, batch) = try sample()
        batch.events[1].questions = ["Chiarisci la data QA"]
        data.coachDocumentReviews = [batch]
        XCTAssertThrowsError(try CoachDocumentReviewStore.stage(batchID: batch.id, expected: batch,
            selected: batch.events.map(\.id), data: &data, now: now))
        XCTAssertTrue(data.coachState.messages.isEmpty); XCTAssertNil(data.coachState.calendarDrafts)
        XCTAssertEqual(data.coachDocumentReviews?.first?.stagedProposalIDs, [])
        let expected = try XCTUnwrap(data.coachDocumentReviews?.first)
        var clarified = expected.events[1]; clarified.questions = []
        try CoachDocumentReviewStore.update(batchID: expected.id, expected: expected, event: clarified, data: &data, now: now)
        let reviewed = try XCTUnwrap(data.coachDocumentReviews?.first)
        _ = try CoachDocumentReviewStore.stage(batchID: reviewed.id, expected: reviewed,
            selected: reviewed.events.map(\.id), data: &data, now: now)
        XCTAssertEqual(data.coachState.calendarDrafts?.count, 2)
    }
    func testRepeatedReadingAndStagePreserveTheExistingEditedDraft() throws {
        var (data, batch) = try sample()
        _ = try CoachDocumentReviewStore.stage(batchID: batch.id, expected: batch, selected: [batch.events[0].id], data: &data, now: now)
        let id = try CoachDocumentReviewStore.save(packet: batch.packet, review: CoachDocumentLocalProposals.analyze(batch.packet), data: &data, now: now)
        XCTAssertEqual(id, batch.id); XCTAssertEqual(data.coachDocumentReviews?.count, 1)
        let current = try XCTUnwrap(data.coachDocumentReviews?.first)
        XCTAssertThrowsError(try CoachDocumentReviewStore.stage(batchID: id, expected: current, selected: [batch.events[0].id], data: &data, now: now))
        XCTAssertEqual(data.coachState.calendarDrafts?.count, 1)
        var changed = current.events[0]; changed.title = "Edited after staging QA"
        XCTAssertThrowsError(try CoachDocumentReviewStore.update(batchID: id, expected: current, event: changed, data: &data, now: now))
        XCTAssertEqual(data.coachState.calendarDrafts?.first?.draft.title, batch.events[0].title)
    }
    func testChangingArchiveOrPhysicalSourceRequiresFreshReviewWithoutMutatingDrafts() throws {
        var (data, batch) = try sample()
        data.coachDocumentReviews?[0].questions = ["New local question QA"]
        XCTAssertThrowsError(try CoachDocumentReviewStore.stage(batchID: batch.id, expected: batch, selected: [batch.events[0].id], data: &data, now: now))
        let current = try XCTUnwrap(data.coachDocumentReviews?.first)
        data.coachDocuments?[0].document.id = UUID()
        XCTAssertTrue(CoachDocumentLibrary.valid(data)); XCTAssertFalse(current.packet.isCurrent(in: data.coachDocuments ?? []))
        XCTAssertThrowsError(try CoachDocumentReviewStore.stage(batchID: current.id, expected: current, selected: [current.events[0].id], data: &data, now: now))
        XCTAssertNil(data.coachState.calendarDrafts)
        var limited = AppData(); limited.coachDocuments = batch.packet.sources
        for index in 0..<20 {
            var packet = batch.packet; packet.id = UUID(); packet.instruction = "Limited reading QA \(index)"
            _ = try CoachDocumentReviewStore.save(packet: packet, review: CoachDocumentLocalProposals.analyze(packet), data: &limited, now: now)
        }
        var extra = batch.packet; extra.id = UUID(); extra.instruction = "One extra reading QA"
        XCTAssertThrowsError(try CoachDocumentReviewStore.save(packet: extra, review: CoachDocumentLocalProposals.analyze(extra), data: &limited, now: now))
        XCTAssertEqual(limited.coachDocumentReviews?.count, 20)
    }
    func testRestoreKeepsReadingHistoryButDoesNotAuthorizeStagingAgainstOldPhysicalIDs() throws {
        var (data, batch) = try sample(); data.studyPDFs = [batch.packet.sources[0].document.id.uuidString: bytes]
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var restored = try StudyFiles.installBackup(data, directory: folder)
        XCTAssertTrue(CoachDocumentLibrary.valid(restored)); XCTAssertEqual(restored.coachDocumentReviews, [batch])
        XCTAssertFalse(batch.packet.isCurrent(in: restored.coachDocuments ?? []))
        XCTAssertThrowsError(try CoachDocumentReviewStore.stage(batchID: batch.id, expected: batch,
            selected: [batch.events[0].id], data: &restored, now: now))
        XCTAssertNil(restored.coachState.calendarDrafts)
    }
    func testStagingTombstonesPreventRecreationAfterConversationRemovalOrAnotherReading() throws {
        var (data, batch) = try sample()
        _ = try CoachDocumentReviewStore.stage(batchID: batch.id, expected: batch, selected: [batch.events[0].id], data: &data, now: now)
        data.coachState.messages = []; data.coachState.calendarDrafts = []
        var packet = batch.packet; packet.id = UUID(); packet.instruction = "Another explicit reading QA"
        _ = try CoachDocumentReviewStore.save(packet: packet, review: CoachDocumentLocalProposals.analyze(packet), data: &data, now: now)
        let next = try XCTUnwrap(data.coachDocumentReviews?.last)
        XCTAssertEqual(CoachDocumentReviewStore.preparedDraftID(for: next.events[0], in: data), batch.events[0].id)
        XCTAssertThrowsError(try CoachDocumentReviewStore.stage(batchID: next.id, expected: next, selected: [next.events[0].id], data: &data, now: now))
        XCTAssertEqual(data.coachState.calendarDrafts?.count, 0)
    }
    func testForgedCitationsAndDuplicateAppointmentsNeverRegisterOrStage() throws {
        var (data, batch) = try sample(), altered = batch.events[0]
        altered.citations[0].quote = "Not in the source QA"
        XCTAssertThrowsError(try CoachDocumentReviewStore.update(batchID: batch.id, expected: batch, event: altered, data: &data, now: now))
        altered = batch.events[0]; altered.id = batch.events[1].id
        try CoachDocumentReviewStore.update(batchID: batch.id, expected: batch, event: altered, data: &data, now: now)
        let duplicate = try XCTUnwrap(data.coachDocumentReviews?.first)
        XCTAssertThrowsError(try CoachDocumentReviewStore.stage(batchID: duplicate.id, expected: duplicate,
            selected: duplicate.events.map(\.id), data: &data, now: now))
        XCTAssertNil(data.coachState.calendarDrafts)
    }
}
