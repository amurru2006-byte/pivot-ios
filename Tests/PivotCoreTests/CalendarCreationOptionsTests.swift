import XCTest
@testable import PivotCore

final class CalendarCreationOptionsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var draft: CoachCalendarDraft {
        .init(title: "Attività QA", start: now.addingTimeInterval(3600), end: now.addingTimeInterval(7200), calendarHint: nil, notes: "Nota QA", endEstimated: false)
    }
    private var options: CalendarCreationOptions {
        .init(location: "Destinazione QA", travel: .init(minutes: 30, origin: "Origine QA"))
    }
    private func item(_ part: CalendarCreationPart) -> CalendarItem {
        .init(id: part.marker, eventIdentifier: part.marker, calendarIdentifier: "qa", calendarTitle: "Lavoro QA", title: part.title,
            start: part.start, end: part.end, location: part.location, notes: part.notes, colorHex: "7EE6CD", isAllDay: false, writable: true, kind: .other)
    }
    func testNoTravelCreatesOnePartWithoutChangingActivityTimes() {
        let parts = CalendarCreationOptions().parts(draft: draft, creationID: UUID())
        XCTAssertEqual(parts.count, 1); XCTAssertEqual(parts[0].start, draft.start); XCTAssertEqual(parts[0].end, draft.end)
    }
    func testSeparateTravelIsContiguousAndDoesNotInflateActivityOrIncome() {
        let parts = options.parts(draft: draft, creationID: UUID())
        XCTAssertEqual(parts.count, 2); XCTAssertEqual(parts[0].title, "Spostamento")
        XCTAssertEqual(parts[0].start, draft.start!.addingTimeInterval(-1800))
        XCTAssertEqual(parts[0].end, draft.start); XCTAssertEqual(parts[1].start, draft.start); XCTAssertEqual(parts[1].end, draft.end)
        XCTAssertTrue(parts[0].isTravel); XCTAssertFalse(parts[1].isTravel)
        XCTAssertFalse(HistoricalIncome.isEligible(item(parts[0]), year: PivotDate.calendar.component(.year, from: now), now: now.addingTimeInterval(86400)))
    }
    func testConflictOnlyDuringTravelIsDetectedAndSharedBoundaryIsNotOverlap() {
        let parts = options.parts(draft: draft, creationID: UUID())
        var other = item(parts[0]); other.id = "other"; other.end = parts[0].start
        XCTAssertTrue(CalendarCreationBundle.conflicts(parts: parts, events: [other]).isEmpty)
        other.end.addTimeInterval(1)
        XCTAssertEqual(CalendarCreationBundle.conflicts(parts: parts, events: [other]).count, 1)
        other.start = draft.end!; other.end = draft.end!.addingTimeInterval(3600)
        XCTAssertTrue(CalendarCreationBundle.conflicts(parts: parts, events: [other]).isEmpty)
    }
    func testSpanningEventsAreReturnedOnlyOnceEvenAcrossBothParts() {
        let parts = options.parts(draft: draft, creationID: UUID()); var other = item(parts[0])
        other.start.addTimeInterval(-3600); other.end = draft.end!.addingTimeInterval(3600)
        XCTAssertEqual(CalendarCreationBundle.conflicts(parts: parts, events: [other]).count, 1)
    }
    func testMidnightAndDSTUseAbsoluteTravelDuration() {
        var value = draft
        value.start = PivotDate.calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 0, minute: 10))!
        value.end = value.start!.addingTimeInterval(3600)
        let parts = options.parts(draft: value, creationID: UUID())
        XCTAssertEqual(parts[0].end.timeIntervalSince(parts[0].start), 1800)
        XCTAssertEqual(PivotDate.calendar.component(.day, from: parts[0].start), 24)
    }
    func testManualTimeWorksForPastEventsWithoutMapsConsent() {
        var value = draft; value.start = now.addingTimeInterval(-7200); value.end = now.addingTimeInterval(-3600)
        XCTAssertNil(options.problem(draft: value, now: now, mapsConsent: false))
    }
    func testInvalidDurationMissingPlacesAndUnsupportedAlertAreRejected() {
        var value = options; value.travel?.minutes = 0; XCTAssertFalse(value.isValid)
        value = options; value.travel?.minutes = 1441; XCTAssertFalse(value.isValid)
        value = options; value.location = ""; XCTAssertNotNil(value.problem(draft: draft, now: now, mapsConsent: false))
        value = options; value.travel?.origin = " "; XCTAssertNotNil(value.problem(draft: draft, now: now, mapsConsent: false))
        value = options; value.alertMinutes = -1; XCTAssertFalse(value.isValid)
        value = options; value.availability = 9; XCTAssertFalse(value.isValid)
    }
    private var mappedOptions: CalendarCreationOptions {
        let request = TravelRouteRequest(origin: .init(name: "A QA", address: "Origine QA", latitude: 45, longitude: 9),
            destination: .init(name: "B QA", address: "Destinazione QA", latitude: 45.1, longitude: 9.1),
            mode: .transit, timing: .arriveBy, date: draft.start!)
        let estimate = TravelEstimate(request: request, fetchedAt: now, departure: draft.start!.addingTimeInterval(-1800),
            arrival: draft.start!, travelSeconds: 1500, distanceMeters: 1200)
        return .init(location: request.destination.address, travel: .init(minutes: 30, origin: request.origin.address, estimate: estimate))
    }
    func testMapsEstimateKeepsWaitingAndRequiresCurrentConsentAndFreshness() {
        let value = mappedOptions
        XCTAssertNil(value.problem(draft: draft, now: now, mapsConsent: true))
        XCTAssertNotNil(value.problem(draft: draft, now: now, mapsConsent: false))
        XCTAssertNotNil(value.problem(draft: draft, now: now.addingTimeInterval(901), mapsConsent: true))
        let parts = value.parts(draft: draft, creationID: UUID())
        XCTAssertEqual(parts[0].end.timeIntervalSince(parts[0].start), 1800, "Include l’attesa, non solo1500secondi sul mezzo")
    }
    func testChangedTimeDestinationOriginOrDurationCannotReuseMapsEstimate() {
        var changed = draft; changed.start!.addTimeInterval(60)
        XCTAssertNotNil(mappedOptions.problem(draft: changed, now: now, mapsConsent: true))
        var value = mappedOptions; value.location = "C QA"
        XCTAssertNotNil(value.problem(draft: draft, now: now, mapsConsent: true))
        value = mappedOptions; value.travel?.origin = "C QA"
        XCTAssertNotNil(value.problem(draft: draft, now: now, mapsConsent: true))
        value = mappedOptions; value.travel?.minutes = 40
        XCTAssertNotNil(value.problem(draft: draft, now: now, mapsConsent: true))
    }
    func testRetryNeedsEveryPartAndRejectsChangedOrPartialWrite() {
        let parts = options.parts(draft: draft, creationID: UUID()); let items = parts.map(item)
        XCTAssertTrue(CalendarCreationBundle.existing(parts: parts, items: items))
        XCTAssertFalse(CalendarCreationBundle.existing(parts: parts, items: Array(items.dropFirst())))
        var changed = items; changed[0].location = "Altro luogo QA"
        XCTAssertFalse(CalendarCreationBundle.existing(parts: parts, items: changed))
        XCTAssertFalse(CalendarCreationBundle.existing(parts: parts, items: items + items))
    }
    func testOptionsAndStableMarkersSurviveBackupWithoutCloudDisclosure() throws {
        let message = CoachMessage(dayKey: PivotDate.key(now), role: .coach, text: "Bozza QA")
        let saved = CoachSavedCalendarDraft(messageID: message.id, dayKey: message.dayKey, draft: draft,
            calendarID: "QA", creationOptions: mappedOptions, creationNeedsVerification: true)
        var data = AppData(); data.coach = CoachState(messages: [message], calendarDrafts: [saved])
        let restored = try BackupCodec.decode(BackupCodec.encodeCompact(data))
        XCTAssertEqual(restored.coachState.calendarDrafts?[0].creationOptions, saved.creationOptions)
        XCTAssertEqual(restored.coachState.calendarDrafts?[0].creationNeedsVerification, true)
        XCTAssertEqual(mappedOptions.parts(draft: restored.coachState.calendarDrafts![0].draft, creationID: restored.coachState.calendarDrafts![0].id),
                       mappedOptions.parts(draft: draft, creationID: saved.id))
        let snapshot = try CoachV8Snapshot.make(message: "Organizza", events: [], data: data, now: now, purpose: "conversation")
        let payload = String(decoding: snapshot.encodedRequest, as: UTF8.self)
        XCTAssertFalse(payload.contains("Origine QA")); XCTAssertFalse(payload.contains("Destinazione QA"))
    }
    func testLegacyOptionsDecodeAndInvalidBackupIsRejected() throws {
        XCTAssertNil(try JSONDecoder().decode(CalendarCreationOptions.self, from: Data("{\"location\":\"\",\"availability\":0}".utf8)).travel)
        var invalid = mappedOptions; invalid.travel?.minutes = -1
        XCTAssertFalse(invalid.isValid)
    }
    func testLostProviderURLCannotTurnTravelIntoIncomeOrWorkout() {
        XCTAssertEqual(EventKind.classify(title: "Spostamento", calendar: "Lavoro"), .other)
        XCTAssertEqual(EventKind.classify(title: "Spostamento", calendar: "Palestra"), .other)
    }
    func testOriginSuggestionRejectsAmbiguousLocationsAndOnlineCalls() {
        var first = item(options.parts(draft: draft, creationID: UUID())[0])
        first.end = draft.start!.addingTimeInterval(-600); first.location = "Origine A QA"
        XCTAssertEqual(CalendarCreationBundle.suggestedOrigin(before: draft.start!, events: [first]), first.location)
        var second = first; second.id = "B QA"; second.location = "Origine B QA"
        XCTAssertEqual(CalendarCreationBundle.suggestedOrigin(before: draft.start!, events: [first, second]), "")
        first.location = "https://call.example.test/qa"
        XCTAssertEqual(CalendarCreationBundle.suggestedOrigin(before: draft.start!, events: [first]), "")
    }
}
