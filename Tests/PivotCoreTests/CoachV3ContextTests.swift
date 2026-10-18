import XCTest
@testable import PivotCore

final class CoachV3ContextTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-18T22:00:00+02:00")!
    private func make(_ data: AppData, message: String = "Sì, continua", events: [CalendarItem] = []) throws -> CoachV8Snapshot {
        try CoachV8Snapshot.make(message: message, events: events, data: data, now: now, purpose: "conversation", protocolVersion: 3)
    }
    private func savedDraft(data: inout AppData) -> CoachSavedCalendarDraft {
        let message = CoachMessage(dayKey: PivotDate.key(now), role: .coach, text: "Quando finisce?", onlineHistoryEligible: true)
        data.coachState.messages.append(message)
        let draft = CoachSavedCalendarDraft(messageID: message.id, dayKey: message.dayKey,
            draft: .init(title: "Attività di prova", start: now.addingTimeInterval(-7200), end: nil, calendarHint: nil, notes: "Nota richiesta", endEstimated: false))
        data.coachState.calendarDrafts = [draft]; return draft
    }
    func testWholeHistoryRetainsKnownTimesAfterFourHundredCharacters() throws {
        var data = AppData()
        let text = String(repeating: "Premessa. ", count: 60) + "Sono stato fuori dalle11:50 alle19:35."
        data.coachState.messages = [.init(dayKey: PivotDate.key(now), role: .user, text: text, onlineHistoryEligible: true)]
        let snapshot = try make(data)
        XCTAssertEqual(snapshot.request.version, 3)
        XCTAssertEqual(snapshot.request.history[0].text, text)
        XCTAssertEqual(snapshot.request.historyOmittedCount, 0)
    }
    func testPartialDraftIsIncludedAsStructuredFactsWithExplicitNulls() throws {
        var data = AppData(); let saved = savedDraft(data: &data)
        let snapshot = try make(data)
        XCTAssertEqual(snapshot.request.draftContext?.first?.title, saved.draft.title)
        XCTAssertEqual(snapshot.request.draftContext?.first?.start, saved.draft.start)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshot.encodedRequest) as? [String: Any])
        let context = try XCTUnwrap((json["draftContext"] as? [[String: Any]])?.first)
        XCTAssertTrue(context["end"] is NSNull); XCTAssertTrue(context["calendarHint"] is NSNull)
        XCTAssertNil(context["calendarID"]); XCTAssertNil(context["id"])
    }
    func testBoundedHistoryDropsWholeTurnsAndKeepsCurrentMessageAndDraft() throws {
        var data = AppData(); let saved = savedDraft(data: &data)
        data.coachState.messages += (0..<20).map { index in
            CoachMessage(dayKey: PivotDate.key(now), role: .user, text: "Messaggio \(index). " + String(repeating: "a", count: 2000), onlineHistoryEligible: true)
        }
        let current = String(repeating: "b", count: 8000)
        let snapshot = try make(data, message: current)
        XCTAssertLessThanOrEqual(snapshot.encodedRequest.count, 24_000)
        XCTAssertEqual(snapshot.request.message, current)
        XCTAssertGreaterThan(snapshot.request.historyOmittedCount ?? 0, 0)
        XCTAssertEqual(snapshot.request.draftContext?.first?.title, saved.draft.title)
        XCTAssertTrue(snapshot.request.history.allSatisfy { $0.text.hasSuffix(String(repeating: "a", count: 2000)) })
    }
    func testCalendarMentionProducesOnlyAliasAndNoAutomaticTitleLocationOrNotes() throws {
        let event = CalendarItem(id: "private-logical", eventIdentifier: "private-native", calendarIdentifier: "private-calendar",
            calendarTitle: "Private Account", title: "Attività privata sintetica", start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600),
            location: "Private origin", notes: "Private notes", colorHex: "123456", isAllDay: false, writable: true, kind: .other)
        let snapshot = try make(AppData(), message: "Cancella Attività privata sintetica", events: [event])
        XCTAssertEqual(snapshot.request.references, ["e0"])
        let json = String(decoding: snapshot.encodedRequest, as: UTF8.self)
        for value in ["private-logical", "private-native", "private-calendar", "Private Account", "Private origin", "Private notes"] { XCTAssertFalse(json.contains(value)) }
    }
    func testHealthLegacyAndCompletedDraftsDoNotBecomeNewContext() throws {
        var data = AppData(); var saved = savedDraft(data: &data); saved.createdEventID = "already-created"
        data.coachState.calendarDrafts = [saved]
        data.coachState.messages += [.init(dayKey: PivotDate.key(now), role: .user, text: "Private health", healthDerived: true, onlineHistoryEligible: true),
                                    .init(dayKey: PivotDate.key(now), role: .coach, text: "Private local legacy")]
        let snapshot = try make(data)
        XCTAssertEqual(snapshot.request.draftContext?.count, 0)
        let text = String(decoding: snapshot.encodedRequest, as: UTF8.self)
        XCTAssertFalse(text.contains("Private health")); XCTAssertFalse(text.contains("Private local legacy"))
    }
    private func bytes(_ snapshot: CoachV8Snapshot, action: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["version":3, "requestID":snapshot.request.requestID,"mode":"actions",
            "eventIDs":[],"reply":"Proposta", "draft":NSNull(),"rewrittenMessage":NSNull(),"actions":[action]])
    }
    func testResponseRejectsExtraActionFieldsAndUnknownAliases() throws {
        let snapshot = try make(AppData())
        let action: [String: Any] = ["kind":"delete","eventID":"e99","title":NSNull(),"start":NSNull(),"end":NSNull(),"notes":NSNull()]
        XCTAssertThrowsError(try CoachV8Response.decode(bytes(snapshot, action: action), for: snapshot.request))
        var extra = action; extra["calendarID"] = "not-allowed"
        XCTAssertThrowsError(try CoachV8Response.decode(bytes(snapshot, action: extra), for: snapshot.request))
    }
}
