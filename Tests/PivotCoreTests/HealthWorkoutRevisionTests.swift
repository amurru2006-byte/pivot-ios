import XCTest
@testable import PivotCore

final class HealthWorkoutRevisionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var event: CalendarItem {
        .init(id: "qa-walk", eventIdentifier: "qa-walk", calendarIdentifier: "qa-calendar", calendarTitle: "QA",
              title: "Camminata QA", start: start, end: start.addingTimeInterval(3600), location: "", notes: "",
              colorHex: "#00AA99", isAllDay: false, writable: true, kind: .workout)
    }
    private var initial: HealthWorkoutSummary {
        .init(id: "qa-health", start: start, end: start.addingTimeInterval(3600), type: "walk", durationSeconds: 3600,
              distanceKM: 4, activeCalories: 200)
    }
    private var revision: HealthWorkoutSummary {
        var value = initial
        value.end = value.end.addingTimeInterval(600); value.durationSeconds = 4200
        value.distanceKM = 5; value.activeCalories = 250; value.averageBPM = 110; value.elevationM = 20
        return value
    }
    private func imported() -> AppData {
        var data = AppData(); data.workoutReviews = []
        HealthImport.apply(initial, to: event, data: &data, now: initial.end)
        return data
    }
    private func merge(_ values: [HealthWorkoutSummary], into data: AppData, events: [CalendarItem]? = nil) -> AppData? {
        HealthReconciliation.merge(workouts: values, sleeps: [:], events: events ?? [event], data: data, now: start.addingTimeInterval(86400))
    }

    func testSameUUIDRefreshesLateMeasurementsAndOwnedTiming() throws {
        let before = imported()
        let after = try XCTUnwrap(merge([revision], into: before))
        let record = try XCTUnwrap(after.records[event.id])
        XCTAssertEqual(record.health, revision)
        XCTAssertEqual(record.actualEnd, revision.end)
        XCTAssertEqual(record.activeMinutes, 70)
        XCTAssertEqual(record.cardio?.distanceKM, 5)
        XCTAssertEqual(record.cardio?.averageBPM, 110)
        XCTAssertEqual(record.cardio?.paceSecondsPerKM, 840)
        XCTAssertEqual(record.status, .completed)
        XCTAssertNil(merge([revision], into: after))
        let report = HealthRefreshReport.make(workouts: [revision], sleeps: [:], before: before, after: after, readAt: revision.end)
        XCTAssertEqual(report.workoutsApplied, 1)
        XCTAssertTrue(after.moves.isEmpty); XCTAssertTrue(after.payments.isEmpty)
        XCTAssertNil(record.calendarTimingNeedsConfirmation)
    }
    func testManualFieldsAndSubjectiveDataSurviveRevision() throws {
        var data = imported()
        data.records[event.id]?.actualEnd = start.addingTimeInterval(3900)
        data.records[event.id]?.activeMinutes = 55
        data.records[event.id]?.notes = "Nota manuale QA"
        data.records[event.id]?.cardio?.distanceKM = 6
        data.records[event.id]?.cardio?.effort = 8
        data.records[event.id]?.cardio?.notes = "Percorso manuale QA"
        let after = try XCTUnwrap(merge([revision], into: data))
        XCTAssertEqual(after.records[event.id]?.actualEnd, data.records[event.id]?.actualEnd)
        XCTAssertEqual(after.records[event.id]?.activeMinutes, 55)
        XCTAssertEqual(after.records[event.id]?.notes, "Nota manuale QA")
        XCTAssertEqual(after.records[event.id]?.cardio?.distanceKM, 6)
        XCTAssertEqual(after.records[event.id]?.cardio?.effort, 8)
        XCTAssertEqual(after.records[event.id]?.cardio?.notes, "Percorso manuale QA")
        XCTAssertEqual(after.records[event.id]?.cardio?.paceSecondsPerKM, 900)
        XCTAssertEqual(after.records[event.id]?.cardio?.activeCalories, 250)
        XCTAssertFalse(after.records[event.id]?.healthManagedFields?.contains(.distance) ?? true)
    }
    func testManualOverrideIsNotReclaimedWhenLaterMeasurementCoincides() throws {
        var data = imported(); data.records[event.id]?.cardio?.distanceKM = 5
        let after = try XCTUnwrap(merge([revision], into: data))
        var next = revision; next.distanceKM = 7
        let final = try XCTUnwrap(merge([next], into: after))
        XCTAssertEqual(final.records[event.id]?.cardio?.distanceKM, 5)
        XCTAssertEqual(final.records[event.id]?.health?.distanceKM, 7)
    }
    func testExplicitlyClearedFieldRemainsEmpty() throws {
        var data = imported(); data.records[event.id]?.cardio?.distanceKM = nil
        let after = try XCTUnwrap(merge([revision], into: data))
        XCTAssertNil(after.records[event.id]?.cardio?.distanceKM)
        var next = revision; next.distanceKM = 7
        XCTAssertNil(try XCTUnwrap(merge([next], into: after)).records[event.id]?.cardio?.distanceKM)
    }
    func testLegacyUnknownProvenanceUpdatesObservationButNotMeasurements() throws {
        var data = imported(); data.records[event.id]?.healthManagedFields = nil
        let after = try XCTUnwrap(merge([revision], into: data))
        XCTAssertEqual(after.records[event.id]?.health, revision)
        XCTAssertEqual(after.records[event.id]?.actualEnd, initial.end)
        XCTAssertEqual(after.records[event.id]?.cardio?.distanceKM, 4)
        XCTAssertEqual(after.records[event.id]?.healthManagedFields, [])
    }
    func testPartialSkippedAndRunningOutcomesAreNotReinterpreted() throws {
        for status in [Completion.partial, .skipped, .running, .pending] {
            var data = imported(); data.records[event.id]?.status = status
            let after = try XCTUnwrap(merge([revision], into: data))
            XCTAssertEqual(after.records[event.id]?.status, status)
            XCTAssertEqual(after.records[event.id]?.actualEnd, initial.end)
            XCTAssertEqual(after.records[event.id]?.cardio?.distanceKM, 4)
            XCTAssertEqual(after.records[event.id]?.health, revision)
        }
    }
    func testCalendarConfirmationMarkerProtectsTimingEvenWhenSameAsSource() throws {
        var data = imported(); data.records[event.id]?.calendarTimingNeedsConfirmation = true
        let after = try XCTUnwrap(merge([revision], into: data))
        XCTAssertEqual(after.records[event.id]?.actualEnd, initial.end)
        XCTAssertEqual(after.records[event.id]?.activeMinutes, 60)
        XCTAssertEqual(after.records[event.id]?.calendarTimingNeedsConfirmation, true)
    }
    func testFirstImportPreservesPreexistingManualCardioAndClock() {
        var data = AppData(); var record = EventRecord(id: event.id, snapshot: event)
        record.actualStart = start.addingTimeInterval(100); record.activeMinutes = 20
        record.cardio = CardioRecord(kind: .walk, distanceKM: 8, effort: 7)
        data.records[event.id] = record
        XCTAssertTrue(HealthImport.apply(initial, to: event, data: &data))
        XCTAssertEqual(data.records[event.id]?.actualStart, record.actualStart)
        XCTAssertEqual(data.records[event.id]?.activeMinutes, 20)
        XCTAssertEqual(data.records[event.id]?.cardio?.distanceKM, 8)
        XCTAssertEqual(data.records[event.id]?.cardio?.activeCalories, 200)
    }
    func testRemovedCardioIsNotRecreatedByRevision() throws {
        var data = imported(); data.records[event.id]?.cardio = nil
        let after = try XCTUnwrap(merge([revision], into: data))
        XCTAssertNil(after.records[event.id]?.cardio)
    }
    func testFirstImportMayReplaceExplicitCalendarSuggestionsNotManualValues() {
        var data = AppData(); var record = EventRecord(id: event.id, snapshot: event)
        record.actualStart = start.addingTimeInterval(-600); record.actualEnd = event.end
        record.activeMinutes = 80; record.timingFromCalendar = true
        data.records[event.id] = record
        HealthImport.apply(initial, to: event, data: &data)
        XCTAssertEqual(data.records[event.id]?.actualStart, initial.start)
        XCTAssertEqual(data.records[event.id]?.activeMinutes, 60)
        XCTAssertEqual(data.records[event.id]?.timingFromCalendar, false)
    }
    func testRevisionCannotCrossManuallyCorrectedOppositeClock() throws {
        var data = imported(); data.records[event.id]?.actualEnd = start.addingTimeInterval(60)
        var next = revision; next.start = start.addingTimeInterval(120)
        let after = try XCTUnwrap(merge([next], into: data))
        XCTAssertEqual(after.records[event.id]?.actualStart, initial.start)
        XCTAssertEqual(after.records[event.id]?.actualEnd, data.records[event.id]?.actualEnd)
        XCTAssertEqual(after.records[event.id]?.activeMinutes, 60)
        XCTAssertEqual(after.records[event.id]?.health, next)
    }
    func testExistingLinkSurvivesMovedOrMissingCalendarWithoutCreatingAnything() throws {
        let after = try XCTUnwrap(merge([revision], into: imported(), events: []))
        XCTAssertEqual(after.records.count, 1)
        XCTAssertEqual(after.records[event.id]?.snapshot, event)
        XCTAssertEqual(after.records[event.id]?.health, revision)
        XCTAssertTrue(after.moves.isEmpty)
    }
    func testDuplicateSourceOrDuplicateLinkDoesNotGuess() {
        var data = imported()
        XCTAssertNil(merge([revision, revision], into: data))
        var record = data.records[event.id]!; record.id = "qa-duplicate"; record.snapshot.id = record.id
        data.records[record.id] = record
        XCTAssertNil(merge([revision], into: data))
    }
    func testEmptyWindowDoesNotErasePreviouslyImportedHistory() {
        let data = imported()
        XCTAssertNil(merge([], into: data, events: []))
        XCTAssertEqual(data.records[event.id]?.health, initial)
    }
    func testNewAmbiguousWorkoutAndAlreadyLinkedDifferentUUIDAreNotApplied() {
        var other = event; other.id = "qa-other"; other.eventIdentifier = "qa-other"
        XCTAssertFalse(EventCoalescer.matches(event, other))
        let ambiguous = merge([initial], into: AppData(), events: [event, other])
        XCTAssertTrue(ambiguous?.records.isEmpty ?? true)
        var next = initial; next.id = "qa-different-source"
        var data = imported(); let record = data.records[event.id]!
        XCTAssertFalse(HealthImport.apply(next, to: event, data: &data))
        XCTAssertEqual(data.records[event.id]?.health, record.health)
    }
    func testInvalidAndFutureSourceCannotBeImported() {
        var invalid = initial; invalid.distanceKM = .nan
        XCTAssertFalse(invalid.isValid)
        var data = AppData(); data.workoutReviews = []
        XCTAssertFalse(HealthImport.apply(invalid, to: event, data: &data))
        var future = initial; future.end = start.addingTimeInterval(2 * 86400)
        XCTAssertNil(merge([invalid, future], into: data))
        var tiny = initial; tiny.distanceKM = .leastNonzeroMagnitude
        XCTAssertNil(tiny.pace)
    }
    func testProvenanceRoundTripAndDefaultExportPrivacy() throws {
        var data = imported()
        let restored = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertEqual(restored.records[event.id]?.healthManagedFields, data.records[event.id]?.healthManagedFields)
        XCTAssertNil(HealthImport.exportData(data).records[event.id]?.healthManagedFields)
        XCTAssertNotNil(HealthImport.exportData(data, allowHealth: true).records[event.id]?.healthManagedFields)
        data.records[event.id]?.health = nil
        XCTAssertNil(HealthImport.exportData(data).records[event.id]?.healthManagedFields)
    }
    func testPendingReviewGetsRevisedObservationWithoutLosingChoice() {
        var data = AppData()
        data.workoutReviews = [.init(workout: initial, eventIDs: [event.id], dismissed: true)]
        let reviews = WorkoutContext.refreshed([revision], events: [event], data: data, now: revision.end)
        XCTAssertEqual(reviews.first?.workout, revision)
        XCTAssertEqual(reviews.first?.dismissed, true)
        XCTAssertEqual(reviews.first?.eventIDs, [event.id])
    }
}
