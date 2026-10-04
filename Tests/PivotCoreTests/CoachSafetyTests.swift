import XCTest
@testable import PivotCore

final class CoachSafetyTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func gym(_ id: String, start: String, end: String) -> CalendarItem {
        CalendarItem(id: id, eventIdentifier: id, externalIdentifier: id, calendarIdentifier: "test", calendarTitle: "Test", title: "palestra", start: date(start), end: date(end), location: "", notes: "", colorHex: "#00FF00", isAllDay: false, writable: true, kind: .workout)
    }
    private func data(for events: [CalendarItem]) -> AppData {
        var data = AppData()
        for event in events {
            var rule = EventRule.defaultRule(for: event)
            rule.travelConfirmed = true
            data.rules[event.id] = rule
        }
        return data
    }
    private var now: Date { date("2026-10-02T12:00:00+02:00") }
    private var first: CalendarItem { gym("first", start: "2026-10-02T08:00:00+02:00", end: "2026-10-02T09:00:00+02:00") }
    private var second: CalendarItem { gym("second", start: "2026-10-02T10:00:00+02:00", end: "2026-10-02T11:00:00+02:00") }

    func testSameTitleRequiresClarificationInsteadOfSelectingLatest() {
        let events = [first, second]
        let result = CoachPlanner.respond(message: "Recupera la palestra", events: events, data: data(for: events), now: now)
        XCTAssertTrue(result.options.isEmpty)
        XCTAssertTrue(result.needsActivityClarification)
        XCTAssertTrue(result.reply.contains("08:00"))
        XCTAssertTrue(result.reply.contains("10:00"))
    }
    func testOccurrenceTimeOrButtonSelectsOnlyRequestedEvent() {
        let events = [first, second]
        let state = data(for: events)
        let typed = CoachPlanner.respond(message: "Recupera la palestra delle 08:00", events: events, data: state, now: now)
        XCTAssertEqual(typed.options.first?.moves.first?.source.id, first.id)
        let tapped = CoachPlanner.respond(message: "Recupera la palestra", events: events, data: state, now: now, targetID: second.id)
        XCTAssertEqual(tapped.options.first?.moves.first?.source.id, second.id)
        let invalid = CoachPlanner.respond(message: "Recupera la palestra", events: events, data: state, now: now, targetID: "invented")
        XCTAssertTrue(invalid.options.isEmpty)
    }
    func testNegationAndSubstringAreNotPermissionToPlanRecovery() {
        let state = data(for: [first])
        for query in ["Non voglio recuperare la palestra", "Non spostare la palestra", "Non ho saltato la palestra", "Ho parlato con il personal della palestra"] {
            XCTAssertTrue(CoachPlanner.respond(message: query, events: [first], data: state, now: now).options.isEmpty, query)
        }
    }
    func testUnmatchedTargetDoesNotBecomeTheOnlyMissedEvent() {
        let result = CoachPlanner.respond(message: "Recupera le ripetizioni", events: [first], data: data(for: [first]), now: now)
        XCTAssertTrue(result.options.isEmpty)
        XCTAssertTrue(result.needsActivityClarification)
    }
    func testTodayRequestNeverOffersTomorrowWhenTodayIsFull() {
        var blocked = gym("blocked", start: "2026-10-02T12:00:00+02:00", end: "2026-10-02T22:00:00+02:00")
        blocked.title = "impegno fisso"; blocked.kind = .tutoring
        let events = [first, blocked]
        let state = data(for: events)
        let today = CoachPlanner.respond(message: "Recupera la palestra oggi", events: events, data: state, now: now)
        XCTAssertTrue(today.options.isEmpty)
        XCTAssertTrue(today.reply.contains("giorno richiesto"))
        let unrestricted = CoachPlanner.respond(message: "Recupera la palestra", events: events, data: state, now: now)
        XCTAssertFalse(unrestricted.options.isEmpty)
        XCTAssertEqual(PivotDate.key(unrestricted.options[0].moves[0].proposedStart), "2026-10-03")
    }
    func testTomorrowAndDayAfterTomorrowAreCalendarDatesAcrossMidnight() {
        let nearMidnight = date("2026-10-02T23:58:00+02:00")
        let events = [first]
        let state = data(for: events)
        for (query, key) in [("Recupera palestra domani", "2026-10-03"), ("Recupera palestra dopodomani", "2026-10-04"), ("Recupera palestra dopo domani", "2026-10-04")] {
            let result = CoachPlanner.respond(message: query, events: events, data: state, now: nearMidnight)
            XCTAssertEqual(result.options.first.map { PivotDate.key($0.moves[0].proposedStart) }, key, query)
        }
        XCTAssertTrue(CoachPlanner.respond(message: "Recupera palestra oggi o domani", events: events, data: state, now: now).options.isEmpty)
    }
    func testTodayNearMidnightDoesNotRollIntoTheNextDay() {
        let result = CoachPlanner.respond(message: "Recupera palestra oggi", events: [first], data: data(for: [first]), now: date("2026-10-02T23:58:00+02:00"))
        XCTAssertTrue(result.options.isEmpty)
        XCTAssertTrue(result.reply.contains("Non rimane uno spazio utile oggi"))
    }
    func testQuickActionDoesNotReadTomorrowInTheEventTitleAsACommand() {
        var item = first
        item.title = "palestra: preparo la scheda per domani"
        let result = CoachPlanner.respond(message: "Voglio recuperare \(item.title)", events: [item], data: data(for: [item]), now: now, targetID: item.id)
        XCTAssertEqual(result.options.first.map { PivotDate.key($0.moves[0].proposedStart) }, "2026-10-02")
    }
    func testStructuredNarratorUsesOnlyVerifiedFactsAndHasNoSideEffects() throws {
        let result = CoachPlanner.respond(message: "Recupera palestra", events: [first], data: data(for: [first]), now: now)
        let option = try XCTUnwrap(result.options.first)
        let valid = "{\"version\":1,\"option_id\":\"\(option.id.uuidString)\",\"tone\":\"supportive\"}"
        let rendered = try XCTUnwrap(CoachNarration.render(valid, verified: result))
        XCTAssertTrue(rendered.contains(option.explanation))
        XCTAssertTrue(rendered.contains(option.consequences))
        XCTAssertTrue(rendered.contains("Calendario non cambia"))
        XCTAssertEqual(result.options.count, 2)
    }
    func testStructuredNarratorRejectsInventedIDsExtraFieldsAndMalformedResponses() {
        let result = CoachPlanner.respond(message: "Recupera palestra", events: [first], data: data(for: [first]), now: now)
        let invalid = [
            "{\"version\":1,\"option_id\":\"invented\",\"tone\":\"neutral\"}",
            "{\"version\":2,\"option_id\":null,\"tone\":\"neutral\"}",
            "{\"version\":true,\"option_id\":null,\"tone\":\"neutral\"}",
            "{\"version\":1,\"option_id\":null,\"tone\":\"evil\"}",
            "{\"version\":1,\"option_id\":null,\"tone\":\"neutral\",\"time\":\"18:00\"}",
            "{\"version\":1,\"tone\":\"neutral\"}",
            "```json\n{\"version\":1,\"option_id\":null,\"tone\":\"neutral\"}\n```",
            "Ho spostato la palestra alle 18:00", "{}", "[]", "{\"version\":1", String(repeating: "x", count: 2049)
        ]
        for output in invalid { XCTAssertNil(CoachNarration.render(output, verified: result), output) }
    }
    func testNarratorDoesNotInventChoicesOrQuestionsForBlockedPlans() {
        let blocked = CoachTurnResult(reply: "Tragitto da confermare", options: [])
        XCTAssertNil(CoachNarration.render("{\"version\":1,\"option_id\":null,\"tone\":\"neutral\"}", verified: blocked))
        let clarify = CoachTurnResult(reply: "Quale attività?", options: [], needsActivityClarification: true)
        XCTAssertNotNil(CoachNarration.render("{\"version\":1,\"option_id\":null,\"tone\":\"neutral\"}", verified: clarify))
        XCTAssertNil(CoachNarration.render("{\"version\":1,\"option_id\":\"invented\",\"tone\":\"neutral\"}", verified: clarify))
    }
}
