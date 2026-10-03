import XCTest
@testable import PivotCore

final class LessonPromptTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-10-03T12:00:00+02:00")!
    func lesson(_ uid: String, offset: Int = 0, recurring: Bool = false, created: Date? = nil) -> CalendarItem {
        let start = now.addingTimeInterval(Double(offset + 1) * 86400)
        return CalendarItem(id: "work|\(uid)|\(Int(start.timeIntervalSince1970))", eventIdentifier: uid, externalIdentifier: uid,
            calendarIdentifier: "work", calendarTitle: "Lavoro", title: "lezione con Sara", start: start,
            end: start.addingTimeInterval(3600), location: "", notes: "", colorHex: "#FFFFFF", isAllDay: false,
            writable: true, kind: .tutoring, recurring: recurring, occurrenceAnchor: recurring ? start : nil, calendarCreatedAt: created)
    }
    func testFirstImportDoesNotPromptForExistingRecurringLessons() {
        let events = (0..<100).map { lesson("existing", offset: $0, recurring: true) }
        var data = AppData()
        XCTAssertTrue(LessonLogistics.pending(events: events, data: data, now: now).isEmpty)
        data.lessonPrompts = LessonPromptState.observed(events, data: data, now: now)
        XCTAssertEqual(data.lessonPrompts?.seenSeries.count, 1)
        XCTAssertTrue(LessonLogistics.pending(events: events, data: data, now: now).isEmpty)
        let later = [lesson("existing", offset: 150, recurring: true)]
        data.lessonPrompts = LessonPromptState.observed(later, data: data, now: now.addingTimeInterval(86400))
        XCTAssertTrue(LessonLogistics.pending(events: later, data: data, now: now).isEmpty)
    }
    func testNewStandaloneEventPromptsButEditingExistingOneDoesNot() {
        let old = lesson("old")
        var data = AppData(); data.lessonPrompts = LessonPromptState.observed([old], data: data, now: now)
        var edited = old; edited.title = "lezione con Luca"; edited.location = "Altro indirizzo"
        edited.start = edited.start.addingTimeInterval(3600)
        let added = lesson("new", created: now.addingTimeInterval(5))
        data.lessonPrompts = LessonPromptState.observed([edited, added], data: data, now: now.addingTimeInterval(10))
        XCTAssertEqual(LessonLogistics.pending(events: [edited, added], data: data, now: now).map(\.id), [added.id])
    }
    func testNewRecurringSeriesPromptsOnlyOnceAndConfirmationStopsLaterOccurrences() {
        let events = (0..<12).map { lesson("new-series", offset: $0, recurring: true, created: now.addingTimeInterval(5)) }
        var data = AppData(); data.lessonPrompts = LessonPromptState.observed([], data: data, now: now)
        data.lessonPrompts = LessonPromptState.observed(events, data: data, now: now.addingTimeInterval(10))
        XCTAssertEqual(LessonLogistics.pending(events: events, data: data, now: now).map(\.id), [events[0].id])
        var record = EventRecord(id: events[0].id, snapshot: events[0])
        record.logistics = LessonLogistics(studentName: "Sara", place: .studentHome, confirmedAt: now.addingTimeInterval(15))
        data.records[record.id] = record
        data.lessonPrompts = LessonPromptState.observed(events, data: data, now: now.addingTimeInterval(20))
        XCTAssertTrue(LessonLogistics.pending(events: events, data: data, now: now).isEmpty)
        XCTAssertNil(data.records[events[1].id]?.logistics)
    }
    func testOldLateSyncedEventDoesNotBecomeANewPrompt() {
        var data = AppData(); data.lessonPrompts = LessonPromptState.observed([], data: data, now: now)
        let old = lesson("late", created: now.addingTimeInterval(-86400))
        data.lessonPrompts = LessonPromptState.observed([old], data: data, now: now.addingTimeInterval(10))
        XCTAssertTrue(LessonLogistics.pending(events: [old], data: data, now: now).isEmpty)
    }
    func testBaselineAndNewPromptSurviveBackupAndRelaunch() throws {
        let old = lesson("old"), added = lesson("new")
        var data = AppData(); data.lessonPrompts = LessonPromptState.observed([old], data: data, now: now)
        data = try BackupCodec.decode(BackupCodec.encode(data))
        data.lessonPrompts = LessonPromptState.observed([old, added], data: data, now: now.addingTimeInterval(10))
        let restored = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertEqual(LessonLogistics.pending(events: [old, added], data: restored, now: now).map(\.id), [added.id])
        XCTAssertEqual(restored.lessonPrompts, data.lessonPrompts)
    }
    func testRecurringFallbackKeyIgnoresOccurrenceTimestampWithoutExternalID() {
        var first = lesson("fallback", recurring: true), second = lesson("fallback", offset: 7, recurring: true)
        first.externalIdentifier = nil; second.externalIdentifier = nil
        XCTAssertEqual(LessonPromptState.seriesKey(first), LessonPromptState.seriesKey(second))
    }
}
