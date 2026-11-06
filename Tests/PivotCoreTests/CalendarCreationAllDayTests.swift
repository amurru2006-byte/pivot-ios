import XCTest
@testable import PivotCore

final class CalendarCreationAllDayTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-01-01T12:00:00+01:00")!
    private func metadata(_ day: String = "2026-10-25", zone: String = "Etc/UTC") -> CalendarCreationAllDay {
        .init(day: day, nativeTimeZoneIdentifier: zone)
    }
    private func draft(_ allDay: CalendarCreationAllDay) throws -> CoachCalendarDraft {
        let interval = try XCTUnwrap(allDay.canonicalInterval)
        return .init(title: "Scadenza QA", start: interval.start, end: interval.end,
            calendarHint: nil, notes: "Metodo QA", endEstimated: false)
    }
    private func item(_ part: CalendarCreationPart) -> CalendarItem {
        .init(id: part.marker, eventIdentifier: part.marker, calendarIdentifier: "qa-calendar", calendarTitle: "QA",
            title: part.title, start: part.start, end: part.end, location: part.location, notes: part.notes,
            colorHex: "7EE6CD", isAllDay: part.isAllDay, writable: true, kind: .other)
    }
    func testAllDayUsesCivilBoundariesIncludingThe25HourDayWithoutChangingTimedLimits() throws {
        let value = metadata(), candidate = try draft(value)
        XCTAssertTrue(value.isValid); XCTAssertEqual(candidate.end!.timeIntervalSince(candidate.start!), 25 * 3600)
        XCTAssertNil(candidate.problem(now: now, calendarID: "qa", allDay: value))
        XCTAssertNotNil(candidate.problem(now: now, calendarID: "qa"))
        let spring = metadata("2026-03-29"), short = try draft(spring)
        XCTAssertEqual(short.end!.timeIntervalSince(short.start!), 23 * 3600)
        XCTAssertNil(short.problem(now: now, calendarID: "qa", allDay: spring))
    }
    func testNativeFloatingDatesRoundTripAcrossDefaultZonesWithoutElapsedTimeArithmetic() throws {
        for day in ["2026-03-29", "2026-10-25", "2026-12-31"] {
            for zoneID in ["Etc/UTC", "America/New_York", "Asia/Tokyo", "Pacific/Auckland"] {
                let zone = try XCTUnwrap(TimeZone(identifier: zoneID)), value = metadata(day, zone: zoneID)
                let native = try XCTUnwrap(value.nativeInterval(currentTimeZone: zone))
                let back = try XCTUnwrap(CalendarCreationAllDay.normalizeNative(start: native.start, end: native.end, timeZone: zone))
                XCTAssertEqual(back, value.canonicalInterval)
            }
        }
        let value = metadata(), zone = try XCTUnwrap(TimeZone(identifier: "Etc/UTC"))
        XCTAssertEqual(value.nativeInterval(currentTimeZone: zone)?.duration, 24 * 3600)
        XCTAssertEqual(value.canonicalInterval?.duration, 25 * 3600)
        let first = try XCTUnwrap(CoachDocumentCivilDay.interval("2026-03-28", timeZone: zone))
        let last = try XCTUnwrap(CoachDocumentCivilDay.interval("2026-03-31", timeZone: zone))
        let normalized = try XCTUnwrap(CalendarCreationAllDay.normalizeNative(start: first.start, end: last.start, timeZone: zone))
        XCTAssertEqual(PivotDate.key(normalized.start), "2026-03-28")
        XCTAssertEqual(PivotDate.key(normalized.end), "2026-03-31")
    }
    func testAChangedDeviceZoneRequiresNewReviewButDoesNotCorruptStoredMetadata() throws {
        let value = metadata(), other = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        XCTAssertNil(value.nativeInterval(currentTimeZone: other)); XCTAssertTrue(value.isValid)
        var options = CalendarCreationOptions(); options.allDay = value
        XCTAssertNotNil(options.problem(draft: try draft(value), now: now, mapsConsent: false, nativeTimeZone: other))
        let roundTrip = try JSONDecoder().decode(CalendarCreationOptions.self, from: JSONEncoder().encode(options))
        XCTAssertEqual(roundTrip.allDay, value)
    }
    func testAllDayCannotExportOrPlanATravelPair() throws {
        let value = metadata(); var options = CalendarCreationOptions(); options.allDay = value
        options.travel = .init(minutes: 20, origin: "Origine QA")
        XCTAssertFalse(options.isValid); XCTAssertTrue(options.parts(draft: try draft(value), creationID: UUID()).isEmpty)
        options.travel = nil; options.appleCalendarTravel = .init(minutes: 20, origin: "Origine QA")
        XCTAssertFalse(options.isValid); XCTAssertTrue(options.occupiedParts(draft: try draft(value), creationID: UUID()).isEmpty)
    }
    func testIdempotencyDistinguishesTimedAndAllDayReceiptsWithTheSameDatesAndTitle() throws {
        let value = metadata(); var options = CalendarCreationOptions(); options.allDay = value
        let parts = options.parts(draft: try draft(value), creationID: UUID())
        XCTAssertEqual(parts.count, 1); XCTAssertTrue(parts[0].isAllDay)
        var written = item(parts[0]); XCTAssertTrue(CalendarCreationBundle.existing(parts: parts, items: [written]))
        let receipt = CalendarCreationReceipt(activity: written, travel: nil)
        XCTAssertTrue(receipt.isValid); var data = AppData()
        XCTAssertTrue(CalendarActivityLinks.capture(id: UUID(), receipt: receipt, options: options, data: &data, now: now))
        XCTAssertNil(data.calendarActivityLinks)
        XCTAssertFalse(CalendarActivityLinks.capture(id: UUID(), receipt: receipt, options: .init(), data: &data, now: now))
        written.isAllDay = false
        XCTAssertFalse(CalendarCreationBundle.existing(parts: parts, items: [written]))
        XCTAssertFalse(CalendarActivityLinks.capture(id: UUID(), receipt: .init(activity: written, travel: nil), options: options, data: &data, now: now))
    }
    func testMalformedCivilDatesNonMidnightAndMixedTimesAreNeverNormalizedSilently() throws {
        XCTAssertFalse(metadata("2026-02-30").isValid)
        XCTAssertFalse(metadata(zone: "QA/Unknown").isValid)
        XCTAssertFalse(metadata("2011-12-30", zone: "Pacific/Apia").isValid)
        let value = metadata(), zone = try XCTUnwrap(TimeZone(identifier: "Etc/UTC"))
        let native = try XCTUnwrap(value.nativeInterval(currentTimeZone: zone))
        XCTAssertNil(CalendarCreationAllDay.normalizeNative(start: native.start.addingTimeInterval(1), end: native.end, timeZone: zone))
        var mixed = try draft(value); mixed.end = mixed.end!.addingTimeInterval(3600)
        var options = CalendarCreationOptions(); options.allDay = value
        XCTAssertFalse(value.matches(mixed)); XCTAssertTrue(options.parts(draft: mixed, creationID: UUID()).isEmpty)
        XCTAssertNotNil(mixed.problem(now: now, calendarID: "qa", allDay: value))
        mixed = try draft(value); mixed.endEstimated = true
        XCTAssertFalse(value.matches(mixed))
    }
    func testAllDayMetadataStaysLocalAndLegacyOptionsStillDecode() throws {
        let value = metadata(), candidate = try draft(value)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(candidate)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["title", "start", "end", "calendarHint", "notes", "endEstimated"]))
        XCTAssertNil(object["allDay"]); XCTAssertNil(object["nativeTimeZoneIdentifier"])
        let legacy = try JSONDecoder().decode(CalendarCreationOptions.self, from: Data("{\"location\":\"\",\"availability\":0}".utf8))
        XCTAssertNil(legacy.allDay); XCTAssertTrue(legacy.isValid)
    }
    func testBackupKeepsTheCivilDayButRejectsAMismatchingDraft() throws {
        let value = metadata(), candidate = try draft(value), day = PivotDate.key(candidate.start!)
        let reply = CoachMessage(dayKey: day, role: .coach, text: "Proposta giornaliera QA")
        var options = CalendarCreationOptions(); options.allDay = value
        var data = AppData(); data.coachState.messages = [reply]
        data.coachState.calendarDrafts = [.init(messageID: reply.id, dayKey: day, draft: candidate, creationOptions: options)]
        let restored = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertEqual(restored.coachState.calendarDrafts?.first?.creationOptions?.allDay, value)
        data.coachState.calendarDrafts?[0].draft.start = candidate.start!.addingTimeInterval(3600)
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(data)))
    }
}
