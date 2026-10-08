import XCTest
@testable import PivotCore

// Synthetic calendar and messages; never a reconstruction of the user's data.
final class CoachV8Tests: XCTestCase {
    private func date(_ hour: String) -> Date { ISO8601DateFormatter().date(from: "2026-10-08T\(hour):00+02:00")! }
    private var now: Date { date("12:00") }
    private func item(_ id: String, title: String, kind: EventKind, start: String, end: String) -> CalendarItem {
        .init(id: id, eventIdentifier: "private-\(id)", calendarIdentifier: "private-calendar", calendarTitle: "Private", title: title, start: date(start), end: date(end), location: "private address", notes: "private notes", colorHex: "#123456", isAllDay: false, writable: true, kind: kind)
    }
    private var lunch: CalendarItem { item("lunch-secret", title: "Pranzo", kind: .meal, start: "11:00", end: "11:45") }
    private var gym: CalendarItem { item("gym-secret", title: "Palestra", kind: .workout, start: "08:00", end: "09:00") }
    private func state(_ events: [CalendarItem]) -> AppData {
        var data = AppData()
        for e in events {
            var rule = EventRule.defaultRule(for: e)
            rule.travelConfirmed = true
            data.rules[e.id] = rule
        }
        return data
    }
    private func response(_ snapshot: CoachV8Snapshot, mode: CoachV8Response.Mode = .plan) -> CoachV8Response {
        .init(version: 1, requestID: snapshot.request.requestID, mode: mode,
              eventIDs: mode == .plan ? [CoachV8Request.Category.lunch, .gym].compactMap { category in snapshot.request.events.first { $0.category == category }?.id } : [],
              reply: "Ho spostato tutto alle 18:00")
    }
    func testNetworkContextMinimizesCalendarAndRetainsTwoTurnConversation() throws {
        let events = [lunch, gym]
        var data = state(events)
        let key = PivotDate.key(now)
        data.coachState.messages = [
            .init(dayKey: key, role: .user, text: "Mi sono svegliato a mezzogiorno"),
            .init(dayKey: key, role: .coach, text: "Da cosa vuoi iniziare?"),
            .init(dayKey: key, role: .system, text: "system-private"),
            .init(dayKey: key, role: .coach, text: "health-private", healthDerived: true),
            .init(dayKey: "2026-10-07", role: .user, text: "yesterday-private")
        ]
        data.coachState.memories = [.init(text: "Preferisco il pranzo prima della palestra")]
        let snapshot = try CoachV8Snapshot.make(message: "Inizia dal pranzo, trova spazio per la palestra", events: events, data: data, now: now)
        let json = String(decoding: try snapshot.request.encoded(), as: UTF8.self)
        for secret in ["lunch-secret", "gym-secret", "private address", "private notes", "private-calendar", "health-private", "system-private", "yesterday-private"] {
            XCTAssertFalse(json.contains(secret), secret)
        }
        XCTAssertEqual(snapshot.request.history.map(\.role), ["user", "assistant"])
        XCTAssertEqual(snapshot.request.memories.count, 1)
        XCTAssertEqual(snapshot.request.events.count, 2)
        XCTAssertTrue(json.contains("mezzogiorno"))
    }
    func testLocalPreviewPreservesOrderDurationsBuffersAndDoesNotMutate() throws {
        let events = [lunch, gym]
        var data = state(events)
        data.rules[gym.id]?.travelBeforeMinutes = 10
        data.rules[gym.id]?.travelAfterMinutes = 15
        let before = try JSONEncoder().encode(data)
        let snapshot = try CoachV8Snapshot.make(message: "Pranzo poi palestra", events: events, data: data, now: now)
        let result = try CoachV8Planner.preview(response(snapshot), snapshot: snapshot, events: events, data: data, now: now)
        let option = try XCTUnwrap(result.options.first)
        XCTAssertEqual(option.moves.map { $0.source.id }, [lunch.id, gym.id])
        XCTAssertEqual(option.moves[0].proposedStart, date("12:05"))
        XCTAssertEqual(option.moves[0].proposedEnd, date("12:50"))
        XCTAssertEqual(option.moves[1].proposedStart, date("13:00"))
        XCTAssertEqual(option.moves[1].proposedEnd, date("14:00"))
        XCTAssertNil(CoachPlanner.validate(option, events: events, data: data, now: now))
        XCTAssertFalse(result.reply.contains("18:00"))
        let original = try JSONSerialization.jsonObject(with: before) as! NSDictionary
        let after = try JSONSerialization.jsonObject(with: JSONEncoder().encode(data)) as! NSDictionary
        XCTAssertEqual(original, after)
        XCTAssertTrue(data.moves.isEmpty)
    }
    func testFixedCalendarBlockRemainsUntouched() throws {
        let block = item("fixed", title: "Impegno", kind: .work, start: "12:00", end: "15:00")
        let events = [lunch, gym, block], data = state(events)
        let snapshot = try CoachV8Snapshot.make(message: "Pranzo poi palestra", events: events, data: data, now: now)
        let result = try CoachV8Planner.preview(response(snapshot), snapshot: snapshot, events: events, data: data, now: now)
        let option = try XCTUnwrap(result.options.first)
        XCTAssertEqual(option.moves[0].proposedStart, date("15:00"))
        XCTAssertFalse(option.moves.contains { $0.source.id == block.id })
    }
    func testNoSpaceNeverCompressesOrMovesToTomorrow() throws {
        let block = item("fixed", title: "Impegno", kind: .work, start: "12:40", end: "22:00")
        let events = [lunch, gym, block]
        var data = state(events)
        data.rules[lunch.id]?.compressionApproved = true
        data.rules[lunch.id]?.minimumMinutes = 15
        let snapshot = try CoachV8Snapshot.make(message: "Pranzo poi palestra", events: events, data: data, now: now)
        let result = try CoachV8Planner.preview(response(snapshot), snapshot: snapshot, events: events, data: data, now: now)
        XCTAssertTrue(result.options.isEmpty)
        XCTAssertTrue(result.reply.contains("nessuna durata"))
    }
    func testUnknownTravelAndPendingMoveRequireResolution() throws {
        let events = [lunch, gym]
        var data = state(events)
        data.rules[lunch.id]?.travelConfirmed = false
        var snapshot = try CoachV8Snapshot.make(message: "Pranzo poi palestra", events: events, data: data, now: now)
        var result = try CoachV8Planner.preview(response(snapshot), snapshot: snapshot, events: events, data: data, now: now)
        XCTAssertTrue(result.options.isEmpty)
        XCTAssertTrue(result.needsActivityClarification)
        data = state(events)
        data.moves = [.init(source: lunch, proposedStart: date("15:00"), proposedEnd: date("15:45"))]
        snapshot = try CoachV8Snapshot.make(message: "Pranzo poi palestra", events: events, data: data, now: now)
        result = try CoachV8Planner.preview(response(snapshot), snapshot: snapshot, events: events, data: data, now: now)
        XCTAssertTrue(result.options.isEmpty)
        XCTAssertTrue(result.reply.contains("già una proposta"))
    }
    func testAmbiguousOccurrenceCannotBeChosenByModel() throws {
        let duplicate = item("lunch-two", title: "Pranzo", kind: .meal, start: "16:00", end: "16:45")
        let events = [lunch, gym, duplicate], data = state(events)
        let snapshot = try CoachV8Snapshot.make(message: "Pranzo poi palestra", events: events, data: data, now: now)
        let result = try CoachV8Planner.preview(response(snapshot), snapshot: snapshot, events: events, data: data, now: now)
        XCTAssertTrue(result.options.isEmpty)
        XCTAssertTrue(result.needsActivityClarification)
    }
    func testChangesAndElapsedTimeInvalidateContext() throws {
        let events = [lunch, gym], data = state(events)
        let snapshot = try CoachV8Snapshot.make(message: "Pranzo poi palestra", events: events, data: data, now: now)
        var changed = events
        changed[0].notes = "new note"
        XCTAssertThrowsError(try CoachV8Planner.preview(response(snapshot), snapshot: snapshot, events: changed, data: data, now: now))
        var changedData = data
        changedData.updatedAt = data.updatedAt.addingTimeInterval(1)
        XCTAssertThrowsError(try CoachV8Planner.preview(response(snapshot), snapshot: snapshot, events: events, data: changedData, now: now))
        XCTAssertThrowsError(try CoachV8Planner.preview(response(snapshot), snapshot: snapshot, events: events, data: data, now: now.addingTimeInterval(121)))
    }
    func testMalformedResponsesCannotPrepareChanges() throws {
        let request = try CoachV8Snapshot.make(message: "Pranzo", events: [lunch], data: state([lunch]), now: now).request
        let good: [String: Any] = ["version": 1, "requestID": request.requestID, "mode": "plan", "eventIDs": ["e0"], "reply": "Proposta"]
        XCTAssertNoThrow(try CoachV8Response.decode(JSONSerialization.data(withJSONObject: good), for: request))
        let variants: [[String: Any]] = [
            good.merging(["version": true]) { _, b in b },
            good.merging(["requestID": UUID().uuidString]) { _, b in b },
            good.merging(["eventIDs": ["invented"]]) { _, b in b },
            good.merging(["eventIDs": ["e0", "e0"]]) { _, b in b },
            good.merging(["mode": "conversation"]) { _, b in b },
            good.merging(["time": "18:00"]) { _, b in b },
            good.merging(["reply": " "]) { _, b in b }
        ]
        for value in variants {
            XCTAssertThrowsError(try CoachV8Response.decode(JSONSerialization.data(withJSONObject: value), for: request))
        }
        XCTAssertThrowsError(try CoachV8Response.decode(Data("```json\n{}".utf8), for: request))
        XCTAssertThrowsError(try CoachV8Response.decode(Data(repeating: 120, count: 8193), for: request))
    }
    func testConversationProducesNoCalendarOptionAndContextIsBounded() throws {
        let data = state([lunch]), events = [lunch]
        let snapshot = try CoachV8Snapshot.make(message: "Mi sono svegliato a mezzogiorno", events: events, data: data, now: now)
        let result = try CoachV8Planner.preview(response(snapshot, mode: .conversation), snapshot: snapshot, events: events, data: data, now: now)
        XCTAssertTrue(result.options.isEmpty)
        XCTAssertThrowsError(try CoachV8Snapshot.make(message: " ", events: events, data: data, now: now))
        XCTAssertThrowsError(try CoachV8Snapshot.make(message: String(repeating: "x", count: 1501), events: events, data: data, now: now))
        let tooMany = (0..<49).map { item("id-\($0)", title: "Pranzo \($0)", kind: .meal, start: "11:00", end: "11:45") }
        XCTAssertThrowsError(try CoachV8Snapshot.make(message: "Pranzo", events: tooMany, data: state(tooMany), now: now))
    }
}
