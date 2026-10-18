import XCTest
@testable import PivotCore

final class CoachHistoricalDraftTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-18T22:51:00+02:00")!
    func testCompletedPastIntervalIsAValidDraftWithoutBeingMovedToTomorrow() {
        let start = ISO8601DateFormatter().date(from: "2026-10-18T11:50:00+02:00")!
        let end = ISO8601DateFormatter().date(from: "2026-10-18T19:35:00+02:00")!
        let draft = CoachCalendarDraft(title: "Attività sintetica già svolta", start: start, end: end, calendarHint: nil, notes: "Note QA", endEstimated: false)
        XCTAssertNil(draft.problem(now: now, calendarID: "qa"))
        XCTAssertEqual(draft.start, start); XCTAssertEqual(draft.end, end)
    }
    func testHistoricalDraftStillRequiresCalendarAndForwardOrderedBoundedDates() {
        var draft = CoachCalendarDraft(title: "Attività QA", start: now.addingTimeInterval(-7200), end: now.addingTimeInterval(-3600),
                                       calendarHint: nil, notes: "", endEstimated: false)
        XCTAssertNotNil(draft.problem(now: now, calendarID: ""))
        draft.end = draft.start; XCTAssertNotNil(draft.problem(now: now, calendarID: "qa"))
        draft.end = now.addingTimeInterval(-3600); draft.start = draft.end?.addingTimeInterval(-86401)
        XCTAssertNotNil(draft.problem(now: now, calendarID: "qa"))
    }
    func testNonfiniteDatesAndFarFutureAreNotAllowed() {
        var draft = CoachCalendarDraft(title: "Attività QA", start: now.addingTimeInterval(367 * 86400),
                                       end: now.addingTimeInterval(367 * 86400 + 3600), calendarHint: nil, notes: "", endEstimated: false)
        XCTAssertNotNil(draft.problem(now: now, calendarID: "qa"))
        draft.start = Date(timeIntervalSinceReferenceDate: -.infinity)
        XCTAssertNotNil(draft.problem(now: now, calendarID: "qa"))
        draft.start = now; draft.end = Date(timeIntervalSinceReferenceDate: .infinity)
        XCTAssertNotNil(draft.problem(now: now, calendarID: "qa"))
    }
}
