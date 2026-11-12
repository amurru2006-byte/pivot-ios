import XCTest
@testable import PivotCore

final class CoachDocumentExchangeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000.375)
    private func sample() throws -> (AppData, CoachDocumentReviewBatch) {
        var data = AppData(); let bytes = Data("%PDF-1.4\nSYNTHETIC EXCHANGE QA\n%%EOF".utf8)
        let source = CoachDocumentSource(document: .init(name: "PRIVATE FILENAME QA.pdf", byteCount: bytes.count), kind: .pdf,
            pageCount: 2, sha256: CoachDocumentSource.digest(bytes), importedAt: now)
        data.coachDocuments = [source]
        let packet = CoachDocumentPacket(createdAt: now, instruction: "Proposte da queste pagine QA", sources: [source],
            pages: [.init(sourceID: source.id, number: 2, text: "Esperienza QA 2030-01-14", reading: .text)])
        _ = try CoachDocumentReviewStore.save(packet: packet, review: CoachDocumentLocalProposals.analyze(packet), data: &data, now: now)
        let batch = try XCTUnwrap(data.coachDocumentReviews?.first)
        _ = try CoachDocumentExchange.begin(expected: batch, data: &data, now: now)
        return (data, try XCTUnwrap(data.coachDocumentReviews?.first))
    }
    private func response(_ batch: CoachDocumentReviewBatch, id: UUID? = nil, quote: String = "Esperienza QA 2030-01-14") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["version": 1, "requestID": (id ?? batch.exchange!.id).uuidString,
            "events": [["kind": "allDay", "title": "Esperienza QA", "day": "2030-01-14", "startClock": NSNull(),
                        "endDay": NSNull(), "endClock": NSNull(), "notes": "", "citations": [
                            ["document": "d1", "page": 2, "quote": quote]], "questions": []]], "questions": []])
    }
    func testManualExportIncludesOnlySelectedTextAndAliasesNotPrivateFileOrNativeIDs() throws {
        let (data, batch) = try sample()
        let text = try CoachDocumentExchange.requestText(batch: batch, sources: data.coachDocuments ?? [])
        XCTAssertTrue(text.contains("Esperienza QA 2030-01-14")); XCTAssertTrue(text.contains("d1"))
        XCTAssertTrue(text.contains(try XCTUnwrap(batch.exchange?.id).uuidString))
        XCTAssertFalse(text.contains("PRIVATE FILENAME")); XCTAssertFalse(text.contains(batch.id.uuidString))
        XCTAssertFalse(text.contains(batch.packet.sources[0].id.uuidString))
        XCTAssertFalse(text.contains(batch.packet.sources[0].document.id.uuidString))
        XCTAssertTrue(data.coachState.messages.isEmpty); XCTAssertNil(data.coachState.calendarDrafts)
    }
    func testNonceSurvivesLocalEncodingAndIsNeverAProviderCredential() throws {
        var (data, batch) = try sample()
        let raw = try JSONEncoder().encode(batch), decoded = try JSONDecoder().decode(CoachDocumentReviewBatch.self, from: raw)
        XCTAssertEqual(decoded, batch); XCTAssertTrue(decoded.exchange?.isValid(for: decoded) == true)
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("access_token"))

        let client = Client(name: "Cliente sintetico", rateCents: 1500)
        let income = IncomeEntry(clientID: client.id, clientName: client.name, date: now, minutes: 60, amountCents: 1500, paidCents: 500)
        data.clients.append(client)
        data.income.append(income)
        data.payments.append(.init(incomeID: income.id, clientName: client.name, date: now, amountCents: 500))

        let archives = try [BackupCodec.encodeCompact(data), BackupCodec.encode(data)]
        for archive in archives {
            var restored = try BackupCodec.decode(archive)
            let persisted = try XCTUnwrap(restored.coachDocumentReviews?.first)
            XCTAssertNotEqual(persisted.packet.createdAt, batch.packet.createdAt)
            XCTAssertEqual(persisted.exchange?.id, batch.exchange?.id)
            XCTAssertEqual(restored.income.first?.outstandingCents, 1000)
            XCTAssertEqual(restored.payments.first?.amountCents, 500)
            let sources = try XCTUnwrap(restored.coachDocuments)
            XCTAssertEqual(try CoachDocumentExchange.requestText(batch: persisted, sources: sources),
                           try CoachDocumentExchange.requestText(batch: batch, sources: data.coachDocuments ?? []))

            var tampered = restored
            tampered.coachDocumentReviews?[0].events[0].title = "Titolo sintetico modificato"
            let changed = try BackupCodec.encodeCompact(tampered)
            XCTAssertThrowsError(try BackupCodec.decode(changed))

            _ = try CoachDocumentExchange.receive(response(batch), expected: persisted, data: &restored, now: now)
            XCTAssertEqual(restored.coachDocumentReviews?.count, 2)
            XCTAssertNil(restored.coachState.calendarDrafts)
        }
    }
    func testValidatedReplyAddsSeparateReviewAndPreservesTheLocalInterpretation() throws {
        var (data, batch) = try sample()
        let id = try CoachDocumentExchange.receive(response(batch), expected: batch, data: &data, now: now)
        XCTAssertEqual(data.coachDocumentReviews?.count, 2)
        XCTAssertEqual(data.coachDocumentReviews?.first?.events, batch.events)
        XCTAssertNil(data.coachDocumentReviews?.first?.exchange)
        let imported = try XCTUnwrap(data.coachDocumentReviews?.last)
        XCTAssertEqual(imported.id, id); XCTAssertEqual(imported.parentReviewID, batch.id)
        XCTAssertEqual(imported.events.first?.timing, .allDay(day: "2030-01-14"))
        XCTAssertTrue(data.coachState.messages.isEmpty); XCTAssertNil(data.coachState.calendarDrafts)
    }
    func testReplyReplayAndDifferentNonceCannotApplyOrCreateAnything() throws {
        var (data, batch) = try sample()
        XCTAssertThrowsError(try CoachDocumentExchange.receive(response(batch, id: UUID()), expected: batch, data: &data, now: now))
        XCTAssertEqual(data.coachDocumentReviews?.count, 1)
        let bytes = try response(batch)
        _ = try CoachDocumentExchange.receive(bytes, expected: batch, data: &data, now: now)
        XCTAssertThrowsError(try CoachDocumentExchange.receive(bytes, expected: batch, data: &data, now: now))
        XCTAssertEqual(data.coachDocumentReviews?.count, 2); XCTAssertNil(data.coachState.calendarDrafts)
    }
    func testNewPreparationInvalidatesThePreviousReplyWithoutLosingItsReading() throws {
        var (data, batch) = try sample(); let bytes = try response(batch)
        _ = try CoachDocumentExchange.begin(expected: batch, data: &data, now: now)
        let current = try XCTUnwrap(data.coachDocumentReviews?.first)
        XCTAssertNotEqual(current.exchange?.id, batch.exchange?.id)
        XCTAssertThrowsError(try CoachDocumentExchange.receive(bytes, expected: current, data: &data, now: now))
        XCTAssertEqual(current.packet, batch.packet); XCTAssertEqual(data.coachDocumentReviews?.count, 1)
    }
    func testEditingOrStagingClearsTheExchangeAndRejectsOldReplies() throws {
        var (data, batch) = try sample(); let bytes = try response(batch)
        var changed = batch.events[0]; changed.notes = "User note QA"
        try CoachDocumentReviewStore.update(batchID: batch.id, expected: batch, event: changed, data: &data, now: now)
        let edited = try XCTUnwrap(data.coachDocumentReviews?.first)
        XCTAssertNil(edited.exchange)
        XCTAssertThrowsError(try CoachDocumentExchange.receive(bytes, expected: edited, data: &data, now: now))
        _ = try CoachDocumentExchange.begin(expected: edited, data: &data, now: now)
        let renewed = try XCTUnwrap(data.coachDocumentReviews?.first)
        _ = try CoachDocumentReviewStore.stage(batchID: renewed.id, expected: renewed, selected: [changed.id], data: &data, now: now)
        XCTAssertNil(data.coachDocumentReviews?.first?.exchange)
    }
    func testChangedPhysicalSourcesAndUngroundedCitationsCannotApply() throws {
        var (data, batch) = try sample()
        XCTAssertThrowsError(try CoachDocumentExchange.receive(response(batch, quote: "Invented QA"), expected: batch, data: &data, now: now))
        data.coachDocuments?[0].document.id = UUID()
        XCTAssertThrowsError(try CoachDocumentExchange.receive(response(batch), expected: batch, data: &data, now: now))
        XCTAssertEqual(data.coachDocumentReviews?.count, 1)
    }
    func testOversizedOrCommandBearingRepliesAreRejectedBeforeAnyMetadataChange() throws {
        var (data, batch) = try sample()
        XCTAssertThrowsError(try CoachDocumentExchange.receive(Data(repeating: 32, count: 64_001), expected: batch, data: &data, now: now))
        var body = try XCTUnwrap(JSONSerialization.jsonObject(with: response(batch)) as? [String: Any])
        body["nativeCalendarID"] = "UNTRUSTED QA"
        XCTAssertThrowsError(try CoachDocumentExchange.receive(JSONSerialization.data(withJSONObject: body), expected: batch, data: &data, now: now))
        XCTAssertEqual(data.coachDocumentReviews?.count, 1); XCTAssertNil(data.coachState.calendarDrafts)
    }
}
