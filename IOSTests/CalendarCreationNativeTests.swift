import XCTest
import EventKit

/// Only unsaved in-memory EKEvent objects. No access request, real calendar
/// lookup, provider request, save or commit is part of these tests.
final class CalendarCreationNativeTests: XCTestCase {
    private func sample(day: String = "2026-10-25", zone: TimeZone = .current) throws -> (CalendarCreationOptions, [CalendarCreationPart]) {
        let metadata = CalendarCreationAllDay(day: day, nativeTimeZoneIdentifier: zone.identifier)
        let interval = try XCTUnwrap(metadata.canonicalInterval)
        let draft = CoachCalendarDraft(title: "Scadenza QA", start: interval.start, end: interval.end,
            calendarHint: nil, notes: "Metodo QA", endEstimated: false)
        var options = CalendarCreationOptions(); options.allDay = metadata
        return (options, options.parts(draft: draft, creationID: UUID()))
    }
    func testEventKitObjectReceivesAllDayFlagAndFloatingBoundariesWithoutSaving() throws {
        let zone = TimeZone.current, (options, parts) = try sample(zone: zone), store = EKEventStore()
        let event = EKEvent(eventStore: store)
        try CalendarCreationNative.assign(try XCTUnwrap(parts.first), options: options, to: event, nativeTimeZone: zone)
        XCTAssertTrue(event.isAllDay); XCTAssertNil(event.timeZone)
        let expected = try XCTUnwrap(options.allDay?.nativeInterval(currentTimeZone: zone))
        XCTAssertEqual(event.startDate, expected.start); XCTAssertEqual(event.endDate, expected.end)
        XCTAssertEqual(try CalendarCreationNative.interval(event, nativeTimeZone: zone, normalizeFloating: true), options.allDay?.canonicalInterval)
    }
    func testQueryAndCivilNormalizationCoverSeveralDefaultZonesAndDST() throws {
        for name in ["Etc/UTC", "America/New_York", "Asia/Tokyo", "Pacific/Auckland"] {
            let zone = try XCTUnwrap(TimeZone(identifier: name))
            for day in ["2026-03-29", "2026-10-25"] {
                let (options, parts) = try sample(day: day, zone: zone)
                let query = try CalendarCreationNative.query(parts: parts, options: options, nativeTimeZone: zone, readOnly: false)
                XCTAssertEqual(CalendarCreationAllDay.normalizeNative(start: query.start, end: query.end, timeZone: zone), options.allDay?.canonicalInterval)
            }
        }
    }
    func testAChangedZoneAllowsOnlyReadOnlyReconciliation() throws {
        let original = try XCTUnwrap(TimeZone(identifier: "Europe/Rome")), changed = try XCTUnwrap(TimeZone(identifier: "Etc/UTC"))
        let (options, parts) = try sample(zone: original)
        XCTAssertThrowsError(try CalendarCreationNative.query(parts: parts, options: options, nativeTimeZone: changed, readOnly: false))
        let read = try CalendarCreationNative.query(parts: parts, options: options, nativeTimeZone: changed, readOnly: true)
        XCTAssertEqual(read, CoachDocumentCivilDay.interval("2026-10-25", timeZone: changed))
        let event = EKEvent(eventStore: EKEventStore()); let before = event.startDate
        XCTAssertThrowsError(try CalendarCreationNative.assign(parts[0], options: options, to: event, nativeTimeZone: changed))
        XCTAssertEqual(event.startDate, before)
    }
    func testMalformedNativeFloatingDatesAreNotSilentlyAccepted() throws {
        let zone = TimeZone.current, (options, parts) = try sample(zone: zone)
        let event = EKEvent(eventStore: EKEventStore())
        try CalendarCreationNative.assign(parts[0], options: options, to: event, nativeTimeZone: zone)
        event.startDate = event.startDate.addingTimeInterval(60)
        XCTAssertThrowsError(try CalendarCreationNative.interval(event, nativeTimeZone: zone, normalizeFloating: true))
        event.endDate = event.startDate
        XCTAssertThrowsError(try CalendarCreationNative.interval(event, nativeTimeZone: zone, normalizeFloating: true))
    }
    func testTimedCreationKeepsAbsoluteTimesAndTheExistingRomeTimeZone() throws {
        let start = Date(timeIntervalSince1970: 1_790_000_000), end = start.addingTimeInterval(3600)
        let draft = CoachCalendarDraft(title: "Attività QA", start: start, end: end, calendarHint: nil, notes: "QA", endEstimated: false)
        let options = CalendarCreationOptions(), part = try XCTUnwrap(options.parts(draft: draft, creationID: UUID()).first)
        let event = EKEvent(eventStore: EKEventStore())
        try CalendarCreationNative.assign(part, options: options, to: event, nativeTimeZone: .current)
        XCTAssertFalse(event.isAllDay); XCTAssertEqual(event.timeZone, PivotDate.calendar.timeZone)
        XCTAssertEqual(try CalendarCreationNative.interval(event, nativeTimeZone: .current, normalizeFloating: true), DateInterval(start: start, end: end))
    }
    func testTravelCannotBeSmuggledIntoAnAllDayExport() throws {
        let (options, parts) = try sample()
        var falseFlag = parts[0]; falseFlag.isAllDay = false
        XCTAssertThrowsError(try CalendarCreationNative.query(parts: [falseFlag], options: options, nativeTimeZone: .current, readOnly: false))
        let trip = CalendarCreationPart(marker: "pivot://travel/" + UUID().uuidString, title: "Viaggio QA", start: parts[0].start,
            end: parts[0].end, location: "QA", notes: "QA", availability: 0, alertMinutes: nil, isTravel: true, isAllDay: true)
        XCTAssertThrowsError(try CalendarCreationNative.query(parts: [trip], options: options, nativeTimeZone: .current, readOnly: false))
        XCTAssertThrowsError(try CalendarCreationNative.query(parts: [parts[0], parts[0]], options: options, nativeTimeZone: .current, readOnly: false))
    }
    func testSameDayKeyCannotAuthorizeDifferentCanonicalTimes() throws {
        let (options, parts) = try sample(); let original = parts[0]
        let altered = CalendarCreationPart(marker: original.marker, title: original.title, start: original.start,
            end: original.end.addingTimeInterval(-3600), location: original.location, notes: original.notes,
            availability: original.availability, alertMinutes: original.alertMinutes, isTravel: false, isAllDay: true)
        XCTAssertThrowsError(try CalendarCreationNative.query(parts: [altered], options: options, nativeTimeZone: .current, readOnly: false))
    }
    func testExternalMultiDayFloatingRangesCanBeNormalizedReadOnly() throws {
        let zone = TimeZone.current
        let first = try XCTUnwrap(CoachDocumentCivilDay.interval("2026-03-28", timeZone: zone))
        let end = try XCTUnwrap(CoachDocumentCivilDay.interval("2026-03-31", timeZone: zone))
        let event = EKEvent(eventStore: EKEventStore()); event.isAllDay = true; event.timeZone = nil
        event.startDate = first.start; event.endDate = end.start
        let beforeStart = event.startDate, beforeEnd = event.endDate
        let normalized = try CalendarCreationNative.interval(event, nativeTimeZone: zone, normalizeFloating: true)
        XCTAssertEqual(PivotDate.key(normalized.start), "2026-03-28"); XCTAssertEqual(PivotDate.key(normalized.end), "2026-03-31")
        XCTAssertEqual(event.startDate, beforeStart); XCTAssertEqual(event.endDate, beforeEnd)
    }
}
