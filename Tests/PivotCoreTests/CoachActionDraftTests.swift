import XCTest
@testable import PivotCore

final class CoachActionDraftTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-02-10T12:00:00+01:00")!
    private func request(_ purpose: String = "conversation") throws -> CoachV8Request {
        try CoachV8Snapshot.make(message: "Una richiesta sintetica", events: [], data: AppData(), now: now, purpose: purpose).request
    }
    private func decoded(_ fields: [String: Any], for request: CoachV8Request) throws -> CoachV8Response {
        let data = try JSONSerialization.data(withJSONObject: fields.merging(["version": 2, "requestID": request.requestID]) { a, _ in a })
        return try CoachV8Response.decode(data, for: request)
    }
    func testCreateAcrossMidnightIsOnlyAValidatedDraft() throws {
        let draft: [String: Any] = ["title": "Chiamata di prova", "start": "2026-02-10T22:00:00+01:00", "end": "2026-02-11T00:00:00+01:00", "calendarHint": "Personale", "notes": "", "endEstimated": false]
        let value = try decoded(["mode": "create", "eventIDs": [], "reply": "Una bozza", "draft": draft, "rewrittenMessage": NSNull()], for: request())
        XCTAssertEqual(value.draft?.end?.timeIntervalSince(value.draft!.start!), 7200)
        XCTAssertNil(value.draft?.problem(now: now, calendarID: "local-id"))
        XCTAssertNotNil(value.draft?.problem(now: now, calendarID: ""))
    }
    func testWrongPurposeAndUnknownFieldsAreRejected() throws {
        let fields: [String: Any] = ["mode": "rewrite", "eventIDs": [], "reply": "Testo", "draft": NSNull(), "rewrittenMessage": "Testo riordinato"]
        XCTAssertThrowsError(try decoded(fields, for: request()))
        XCTAssertEqual(try decoded(fields, for: request("rewrite")).rewrittenMessage, "Testo riordinato")
        XCTAssertThrowsError(try decoded(fields.merging(["extra": "untrusted"]) { _, b in b }, for: request("rewrite")))
    }
    func testCalendarMatchingIsExactAndDoesNotHideAmbiguity() {
        let choices = [(id: "a", title: " Personale "), (id: "b", title: "Personale"), (id: "c", title: "Personale lavoro")]
        XCTAssertEqual(CoachCalendarDraft.matchingCalendarIDs(hint: "PERSONALE", choices: choices), ["a", "b"])
        XCTAssertTrue(CoachCalendarDraft.matchingCalendarIDs(hint: "Pers", choices: choices).isEmpty)
    }
    func testDuplicateWithDifferentNotesCannotBeReportedAsSaved() {
        let draft = CoachCalendarDraft(title: "Spesa di prova", start: nil, end: nil, calendarHint: nil, notes: "Latte e uova", endEstimated: false)
        XCTAssertNoThrow(try draft.checkExistingNotes(" Latte e uova\n"))
        XCTAssertThrowsError(try draft.checkExistingNotes("Latte"))
    }
    func testUserConfirmedCalendarAliasSurvivesRenameButNeverUsesMissingCalendar() {
        let choices = [(id: "a", title: "Un nome diverso"), (id: "b", title: "Lavoro")]
        XCTAssertEqual(CoachCalendarDraft.selectedCalendar(hint: "CASA", choices: choices, aliases: ["casa": "a"], preferred: "b"), "a")
        XCTAssertNil(CoachCalendarDraft.selectedCalendar(hint: "Casa", choices: choices, aliases: ["casa": "deleted"], preferred: "b"))
        XCTAssertEqual(CoachCalendarDraft.selectedCalendar(hint: nil, choices: choices, aliases: [:], preferred: "b"), "b")
    }
    func testRewriteHasNoCalendarOrHistoryAndDoesNotTruncateLongText() throws {
        let message = String(repeating: "Devo studiare e fare la spesa. ", count: 100)
        let snapshot = try CoachV8Snapshot.make(message: message, events: [], data: AppData(), now: now, purpose: "rewrite")
        XCTAssertEqual(snapshot.request.message, message.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertEqual(snapshot.request.version, 2)
        XCTAssertTrue(snapshot.request.events.isEmpty); XCTAssertTrue(snapshot.request.history.isEmpty)
        XCTAssertThrowsError(try CoachV8Snapshot.make(message: message, events: [], data: AppData(), now: now))
    }
    func testPrivateDataRestoredLocallyAndChangedNumbersOrNegationsRejected() throws {
        let raw = "Non telefonare alle 22. Scrivi a esempio@example.test, poi a altro@example.test senza allegati."
        let draft = CoachRewriteDraft(original: raw, events: [], data: AppData())
        XCTAssertFalse(draft.message.contains("example.test"))
        XCTAssertEqual(try draft.restore(draft.message), raw)
        XCTAssertThrowsError(try draft.restore(draft.message.replacingOccurrences(of: "22", with: "23")))
        XCTAssertThrowsError(try draft.restore(draft.message.replacingOccurrences(of: "Non ", with: "")))
        XCTAssertThrowsError(try draft.restore(draft.message + draft.message))
    }
}
