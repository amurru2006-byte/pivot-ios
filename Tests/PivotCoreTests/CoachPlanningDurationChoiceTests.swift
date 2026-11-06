import XCTest
@testable import PivotCore

final class CoachPlanningDurationChoiceTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-19T12:00:00+02:00")!
    private func fixture(minutes: Double = 60, samples: [Double] = [60, 75, 90]) -> (CalendarItem, TrainingLibrary) {
        let plan = TrainingPlan(payload: .init(formatVersion: 1, name: "Scheda QA", days: [
            .init(id: "duration-day-qa", name: "Giorno QA", exercises: [
                .init(id: "duration-exercise-qa", name: "Esercizio QA", sets: 1, reps: "6", restSeconds: 60, coachNotes: "")])]))
        var library = TrainingLibrary(plans: [plan])
        for (index, minutes) in samples.enumerated() {
            var session = library.makeSession(plan: plan, day: plan.payload.days[0], eventID: nil,
                now: now.addingTimeInterval(-Double(index + 1) * 86400))
            session.end = session.start.addingTimeInterval(minutes * 60)
            session.exercises[0].sets[0].kg = 20; session.exercises[0].sets[0].reps = 6; session.exercises[0].sets[0].done = true
            library.sessions.append(session)
        }
        let source = CalendarItem(id: "duration-event-qa", eventIdentifier: "native-duration-qa", calendarIdentifier: "qa",
            calendarTitle: "QA", title: "Palestra QA", start: now.addingTimeInterval(-7200),
            end: now.addingTimeInterval(-7200 + minutes * 60), location: "", notes: "", colorHex: "7EE6CD",
            isAllDay: false, writable: true, kind: .workout)
        return (source, library)
    }
    private func choice(_ source: CalendarItem, _ library: TrainingLibrary) throws -> CoachPlanningDurationChoice {
        try .make(source: source, planID: library.plans[0].id, dayID: library.plans[0].payload.days[0].id, library: library, now: now)
    }
    func testExplicitSelectionAdoptsComparableMedianAndShowsProvisionalEvidence() throws {
        let (source, library) = fixture()
        let result = try choice(source, library)
        XCTAssertEqual(result.activityMinutes, 75); XCTAssertEqual(result.observedMedianMinutes, 75)
        XCTAssertEqual(result.sampleIDs.count, 3); XCTAssertTrue(result.provisional)
        XCTAssertNoThrow(try result.revalidated(source: source, library: library, now: now.addingTimeInterval(1)))
    }
    func testEstimateNeverShortensExistingCalendarDuration() throws {
        let (source, library) = fixture(minutes: 120)
        XCTAssertEqual(try choice(source, library).activityMinutes, 120)
    }
    func testNoEstimateFromSparseIncompleteOrWrongDayHistory() {
        for samples in [[], [60], [60, 90]] {
            let (source, library) = fixture(samples: samples)
            XCTAssertThrowsError(try choice(source, library))
        }
        let (source, initial) = fixture()
        var library = initial; library.sessions[0].exercises[0].sets[0].done = false
        XCTAssertThrowsError(try choice(source, library))
        library = initial; library.sessions[0].dayID = "other-day-qa"
        XCTAssertThrowsError(try choice(source, library))
    }
    func testUnknownOrDuplicateSelectionAndNonGymActivityAreRejected() throws {
        let (source, library) = fixture()
        XCTAssertThrowsError(try CoachPlanningDurationChoice.make(source: source, planID: UUID(), dayID: "duration-day-qa", library: library, now: now))
        var duplicate = library; duplicate.plans.append(library.plans[0])
        XCTAssertThrowsError(try choice(source, duplicate))
        var other = source; other.kind = .study
        XCTAssertThrowsError(try choice(other, library))
        other = source; other.title = "Corsa"
        XCTAssertThrowsError(try choice(other, library))
    }
    func testChangedWorkloadOrNewComparableHistoryRequiresAnotherReview() throws {
        let (source, initial) = fixture()
        let result = try choice(source, initial)
        var changed = initial; changed.plans[0].payload.days[0].exercises[0].restSeconds = 120
        XCTAssertThrowsError(try result.revalidated(source: source, library: changed, now: now))
        changed = initial
        var extra = initial.sessions[0]; extra.id = UUID(); extra.start = now.addingTimeInterval(-7200); extra.end = extra.start.addingTimeInterval(4200)
        changed.sessions.append(extra)
        XCTAssertThrowsError(try result.revalidated(source: source, library: changed, now: now))
    }
    func testDifferentLoadsDoNotBecomeDifferentTimedWorkloadOrEnterTheChoice() throws {
        let (source, initial) = fixture()
        let result = try choice(source, initial)
        var changed = initial; changed.sessions[0].exercises[0].sets[0].kg = 123.5
        XCTAssertNoThrow(try result.revalidated(source: source, library: changed, now: now))
        let raw = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        for secret in ["kg", "coachNotes", "notes", "123.5"] { XCTAssertFalse(raw.contains(secret)) }
    }
    func testChoiceValidationRejectsNaNOutOfBoundsAndRepeatedSampleIdentity() throws {
        let (source, library) = fixture()
        var value = try choice(source, library)
        value.sampleMinutes[0] = .nan; XCTAssertFalse(value.isValid)
        value = try choice(source, library); value.activityMinutes = 0; XCTAssertFalse(value.isValid)
        value = try choice(source, library); value.sampleIDs[1] = value.sampleIDs[0]; XCTAssertFalse(value.isValid)
    }
    func testFiveComparableSamplesUsePrudentDurationWithoutGuarantee() throws {
        let (source, library) = fixture(samples: [60, 65, 75, 90, 100])
        let value = try choice(source, library)
        XCTAssertFalse(value.provisional); XCTAssertEqual(value.observedMedianMinutes, 75)
        XCTAssertGreaterThanOrEqual(value.activityMinutes, 75)
    }
}
