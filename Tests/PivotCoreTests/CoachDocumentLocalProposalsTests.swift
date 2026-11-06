import XCTest
@testable import PivotCore

final class CoachDocumentLocalProposalsTests: XCTestCase {
    private func packet(_ text: String, reading: CoachDocumentPage.Reading = .text) -> CoachDocumentPacket {
        let now = Date(timeIntervalSince1970: 1_790_000_000), bytes = Data("%PDF-1.4\nSYNTHETIC QA\n%%EOF".utf8)
        let source = CoachDocumentSource(document: .init(name: "QA.pdf", byteCount: bytes.count), kind: .pdf,
            pageCount: 1, sha256: CoachDocumentSource.digest(bytes), importedAt: now)
        return .init(createdAt: now, instruction: "Prepara proposte locali", sources: [source],
            pages: [.init(sourceID: source.id, number: 1, text: text, reading: reading)])
    }
    func testSeveralExplicitDatesBecomeSeparateAllDayProposalsWithOriginalCitations() throws {
        let p = packet("Prima esperienza 2030-01-14\nSeconda esperienza 2030-01-15")
        let review = try CoachDocumentLocalProposals.analyze(p)
        XCTAssertEqual(review.events.count, 2)
        XCTAssertEqual(review.events.map(\.timing), [.allDay(day: "2030-01-14"), .allDay(day: "2030-01-15")])
        XCTAssertTrue(review.events.allSatisfy { $0.startClock == nil && $0.citations[0].isGrounded(in: p) })
    }
    func testExplicitTimedRangeStillRequiresUserTimeZoneReview() throws {
        let review = try CoachDocumentLocalProposals.analyze(packet("Laboratorio 2030-01-14 09:00-11:00"))
        let event = try XCTUnwrap(review.events.first)
        XCTAssertEqual(event.startClock, "09:00"); XCTAssertEqual(event.endClock, "11:00")
        XCTAssertTrue(event.questions.contains { $0.contains("Europe/Rome") })
        guard case .needsClarification = event.timing else { return XCTFail("A clock does not authorize an assumed zone") }
    }
    func testADeadlineWithOneClockNeverReceivesAnInventedEnd() throws {
        let event = try XCTUnwrap(CoachDocumentLocalProposals.analyze(packet("Scadenza 2030-01-14 23:44")).events.first)
        XCTAssertEqual(event.kind, .timed); XCTAssertNil(event.endClock); XCTAssertNil(event.endDay)
        guard case .needsClarification = event.timing else { return XCTFail("Missing end must stay unresolved") }
    }
    func testMissingYearAmbiguousSlashDatesAndMultipleDatesAreDisclosedNotGuessed() throws {
        for text in ["Laboratorio il 14 gennaio", "Laboratorio 03/04/2030", "Dal 2030-01-14 al 2030-01-15"] {
            let review = try CoachDocumentLocalProposals.analyze(packet(text))
            XCTAssertTrue(review.events.isEmpty); XCTAssertFalse(review.questions.isEmpty)
        }
    }
    func testInvalidDayDotClockAndForeignZoneRequireClarification() throws {
        for text in ["Laboratorio 2030-02-30", "Scadenza 2030-01-14 alle 23.44", "Laboratorio 2030-01-14 09:00-11:00 UTC"] {
            let event = try XCTUnwrap(CoachDocumentLocalProposals.analyze(packet(text)).events.first)
            XCTAssertFalse(event.questions.isEmpty)
            guard case .needsClarification = event.timing else { return XCTFail("Unclear fields must not stage") }
        }
    }
    func testOverflowReturnsNoSilentPartialTwentyEventResult() throws {
        let text = (1...21).map { "Attività QA \($0) 2030-01-\(String(format: "%02d", $0))" }.joined(separator: "\n")
        let review = try CoachDocumentLocalProposals.analyze(packet(text))
        XCTAssertTrue(review.events.isEmpty); XCTAssertTrue(review.questions.contains { $0.contains("20") })
    }
    func testRepeatedRowsAreDisclosedAndNeverCreateTwinProposals() throws {
        let review = try CoachDocumentLocalProposals.analyze(packet("QA 2030-01-14\nQA 2030-01-14"))
        XCTAssertTrue(review.events.isEmpty); XCTAssertTrue(review.questions.contains { $0.contains("ripetute") })
    }
    func testUnreadablePagesNeverBecomeGeneratedContent() throws {
        let review = try CoachDocumentLocalProposals.analyze(packet("", reading: .unreadable))
        XCTAssertTrue(review.events.isEmpty); XCTAssertTrue(review.questions.contains { $0.contains("non sono leggibili") })
    }
}
