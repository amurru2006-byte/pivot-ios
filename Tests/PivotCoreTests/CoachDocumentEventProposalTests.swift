import XCTest
@testable import PivotCore

final class CoachDocumentEventProposalTests: XCTestCase {
    private func packet() -> CoachDocumentPacket {
        let now = Date(timeIntervalSince1970: 1_790_000_000), bytes = Data("%PDF-1.4\nQA\n%%EOF".utf8)
        let source = CoachDocumentSource(document: .init(name: "Programma QA.pdf", byteCount: bytes.count), kind: .pdf,
            pageCount: 2, sha256: CoachDocumentSource.digest(bytes), importedAt: now)
        return .init(createdAt: now, instruction: "Prepara solo proposte da controllare", sources: [source],
            pages: [.init(sourceID: source.id, number: 1,
                text: "Laboratorio QA: 12 aprile 2027. Esperienza QA: 13 aprile 2027 dalle 17:20 alle 18:05.", reading: .text)])
    }
    private func event() -> [String: Any] {
        ["kind": "allDay", "title": "Laboratorio QA", "day": "2027-04-12", "startClock": NSNull(),
         "endDay": NSNull(), "endClock": NSNull(), "notes": "Materiale QA da controllare.",
         "citations": [["document": "d1", "page": 1, "quote": "Laboratorio QA: 12 aprile 2027."]], "questions": []]
    }
    private func body(_ events: [[String: Any]], packet: CoachDocumentPacket, questions: [String] = []) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["version": 1, "requestID": packet.id.uuidString, "events": events, "questions": questions])
    }
    func testDateOnlyBecomesAnAllDayProposalWithoutAnInventedHour() throws {
        let p = packet(), review = try CoachDocumentEventResponse.decode(body([event()], packet: p), packet: p)
        XCTAssertEqual(review.events.count, 1)
        XCTAssertEqual(review.events[0].timing, .allDay(day: "2027-04-12"))
        XCTAssertNil(review.events[0].startClock); XCTAssertNil(review.events[0].endClock)
        XCTAssertEqual(review.events[0].references, [.init(sourceID: p.sources[0].id, pages: [1])])
        XCTAssertFalse(review.events[0].notes.contains("00:00"))
    }
    func testCivilDatesRejectNormalizationAndMissingYears() {
        for value in ["12/04", "2027-02-29", "2027-04-31", "2027-4-12", "2027-00-01", "2027-04-00"] {
            XCTAssertNil(CoachDocumentCivilDay.interval(value), value)
        }
        XCTAssertNotNil(CoachDocumentCivilDay.interval("2028-02-29"))
    }
    func testCivilBoundariesKeepDaylightSavingDaysInsteadOfAdding86400Seconds() throws {
        let spring = try XCTUnwrap(CoachDocumentCivilDay.interval("2026-03-29"))
        let autumn = try XCTUnwrap(CoachDocumentCivilDay.interval("2026-10-25"))
        XCTAssertEqual(spring.duration, 23 * 3600); XCTAssertEqual(autumn.duration, 25 * 3600)
        XCTAssertEqual(PivotDate.key(spring.end), "2026-03-30")
        XCTAssertEqual(PivotDate.key(autumn.end), "2026-10-26")
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        XCTAssertEqual(try XCTUnwrap(CoachDocumentCivilDay.interval("2026-03-08", timeZone: zone)).duration, 23 * 3600)
    }
    func testTimedProposalCannotGuessAmbiguousHoursDurationOrTheNextDay() throws {
        XCTAssertNil(CoachDocumentCivilDay.instant(day: "2026-03-29", clock: "02:30"))
        XCTAssertNil(CoachDocumentCivilDay.instant(day: "2026-10-25", clock: "02:30"))
        XCTAssertNil(CoachDocumentCivilDay.instant(day: "2027-04-12", clock: "24:00"))
        var p = packet(); p.instruction += " Per questa prova uso inizio23:00 e fine01:00, specificando il giorno di fine."
        var raw = event(); raw["kind"] = "timed"; raw["startClock"] = "23:00"; raw["endClock"] = "01:00"
        var proposed = try CoachDocumentEventResponse.decode(body([raw], packet: p), packet: p).events[0]
        guard case .needsClarification = proposed.timing else { return XCTFail("An overnight end was invented") }
        raw["endDay"] = "2027-04-13"
        proposed = try CoachDocumentEventResponse.decode(body([raw], packet: p), packet: p).events[0]
        guard case .needsClarification = proposed.timing else { return XCTFail("A source time zone was assumed") }
        p.instruction += " Il fuso confermato per questa prova è Europe/Rome."
        proposed = try CoachDocumentEventResponse.decode(body([raw], packet: p), packet: p).events[0]
        guard case .timed(let start, let end) = proposed.timing else { return XCTFail("Explicit overnight time was lost") }
        XCTAssertEqual(end.timeIntervalSince(start), 2 * 3600)
        raw["endClock"] = NSNull()
        proposed = try CoachDocumentEventResponse.decode(body([raw], packet: p), packet: p).events[0]
        guard case .needsClarification = proposed.timing else { return XCTFail("A duration was invented") }
    }
    func testResponseCannotCarryNativeCommandsOrUseAnotherRequest() throws {
        let p = packet(); var raw = event(); raw["calendarID"] = "qa-forbidden-native-id"
        XCTAssertThrowsError(try CoachDocumentEventResponse.decode(body([raw], packet: p), packet: p))
        XCTAssertThrowsError(try CoachDocumentEventResponse.decode(body([event()], packet: packet()), packet: p))
        let valid = try body([event()], packet: p), string = try XCTUnwrap(String(data: valid, encoding: .utf8))
        let duplicatedKey = "{\"version\":1," + String(string.dropFirst())
        XCTAssertThrowsError(try CoachDocumentEventResponse.decode(Data(duplicatedKey.utf8), packet: p))
    }
    func testSourcesPagesQuotesAndDuplicateEventsAreVerified() throws {
        let p = packet()
        for quote in [["document": "d2", "page": 1, "quote": "Laboratorio QA: 12 aprile 2027."] as [String: Any],
            ["document": "d1", "page": 2, "quote": "Laboratorio QA: 12 aprile 2027."],
            ["document": "d1", "page": 1, "quote": "An invented quotation"]] {
            var raw = event(); raw["citations"] = [quote]
            XCTAssertThrowsError(try CoachDocumentEventResponse.decode(body([raw], packet: p), packet: p))
        }
        XCTAssertThrowsError(try CoachDocumentEventResponse.decode(body([event(), event()], packet: p), packet: p))
    }
    func testSeveralEventsAndClarificationWithoutAnyEventRemainReviewable() throws {
        var p = packet(); p.instruction += " Gli orari di questa prova sono Europe/Rome."
        var timed = event(); timed["title"] = "Esperienza QA"; timed["kind"] = "timed"
        timed["day"] = "2027-04-13"; timed["startClock"] = "17:20"; timed["endClock"] = "18:05"
        timed["citations"] = [["document": "d1", "page": 1, "quote": "Esperienza QA: 13 aprile 2027 dalle 17:20 alle 18:05."]]
        let review = try CoachDocumentEventResponse.decode(body([event(), timed], packet: p), packet: p)
        XCTAssertEqual(review.events.count, 2)
        guard case .timed = review.events[1].timing else { return XCTFail("Explicit time was discarded") }
        let clarification = try CoachDocumentEventResponse.decode(body([], packet: p, questions: ["Quale anno intendi?"]), packet: p)
        XCTAssertTrue(clarification.events.isEmpty); XCTAssertEqual(clarification.questions, ["Quale anno intendi?"])
        XCTAssertThrowsError(try CoachDocumentEventResponse.decode(body([], packet: p), packet: p))
    }
    func testMissingDateOrUncertaintyCannotTurnIntoAnAllDayGuess() throws {
        let p = packet(); var raw = event(); raw["day"] = NSNull()
        var review = try CoachDocumentEventResponse.decode(body([raw], packet: p), packet: p)
        guard case .needsClarification = review.events[0].timing else { return XCTFail("Missing year was invented") }
        raw = event(); raw["questions"] = ["Conferma il fuso orario della fonte."]
        review = try CoachDocumentEventResponse.decode(body([raw], packet: p), packet: p)
        guard case .needsClarification = review.events[0].timing else { return XCTFail("Uncertainty was ignored") }
        raw = event(); raw["day"] = "2028-04-12"
        review = try CoachDocumentEventResponse.decode(body([raw], packet: p), packet: p)
        guard case .needsClarification = review.events[0].timing else { return XCTFail("An absent year was inferred") }
        raw = event(); raw["citations"] = [["document": "d1", "page": 1, "quote": "Esperienza QA: 13 aprile 2027 dalle 17:20 alle 18:05."]]
        review = try CoachDocumentEventResponse.decode(body([raw], packet: p), packet: p)
        guard case .needsClarification = review.events[0].timing else { return XCTFail("An explicit quoted time was discarded") }
        XCTAssertThrowsError(try CoachDocumentEventResponse.decode(Data(repeating: 32, count: 64_001), packet: p))
    }
}
