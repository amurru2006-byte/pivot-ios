import XCTest
@testable import PivotCore

final class Pivot074Tests: XCTestCase {
    private func exercise() -> TrainingExercise {
        TrainingExercise(id: "bench", name: "Bench Press", sets: 4, reps: "4", restSeconds: 120, coachNotes: "")
    }
    private func event(title: String = "Camminata") -> CalendarItem {
        let start = ISO8601DateFormatter().date(from: "2026-10-07T10:00:00+02:00")!
        return CalendarItem(id: "cardio", eventIdentifier: "cardio", calendarIdentifier: "test", calendarTitle: "Test",
                            title: title, start: start, end: start.addingTimeInterval(3600), location: "", notes: "",
                            colorHex: "#FFFFFF", isAllDay: false, writable: true, kind: .workout)
    }

    func testOldTrainingSetDecodesAsWorkingSet() throws {
        struct Legacy: Codable { var id = UUID(); var number = 1; var kg: Double? = 70; var reps: Int? = 4; var done = true }
        let decoded = try JSONDecoder().decode(TrainingSet.self, from: JSONEncoder().encode(Legacy()))
        XCTAssertEqual(decoded.resolvedKind, .working)
        XCTAssertFalse(decoded.reachesFailure)
        XCTAssertNil(decoded.loadFraction)
        XCTAssertNil(decoded.isAdditional)
    }

    func testOnlyAddedUnfinishedSetsCanBeRemoved() {
        let prescribed = [
            TrainingSet(number: 1, kind: .working),
            TrainingSet(number: 2, kind: .working),
            TrainingSet(number: 3, kind: .working, isAdditional: true)
        ]
        XCTAssertFalse(TrainingSetTemplate.canRemove(prescribed, at: 0, prescribedWorkingSets: 2))
        XCTAssertFalse(TrainingSetTemplate.canRemove(prescribed, at: 1, prescribedWorkingSets: 2))
        XCTAssertTrue(TrainingSetTemplate.canRemove(prescribed, at: 2, prescribedWorkingSets: 2))
        var completed = prescribed
        completed[2].done = true
        XCTAssertFalse(TrainingSetTemplate.canRemove(completed, at: 2, prescribedWorkingSets: 2))

        let legacy = [
            TrainingSet(number: 1, kind: .warmup),
            TrainingSet(number: 2, kind: .working),
            TrainingSet(number: 3, kind: .working),
            TrainingSet(number: 4, kind: .backoff)
        ]
        XCTAssertTrue(TrainingSetTemplate.canRemove(legacy, at: 0, prescribedWorkingSets: 2))
        XCTAssertFalse(TrainingSetTemplate.canRemove(legacy, at: 1, prescribedWorkingSets: 2))
        XCTAssertFalse(TrainingSetTemplate.canRemove(legacy, at: 2, prescribedWorkingSets: 2))
        XCTAssertTrue(TrainingSetTemplate.canRemove(legacy, at: 3, prescribedWorkingSets: 2))
        var marked = TrainingSetTemplate.markingOrigins(legacy, prescribedWorkingSets: 2)
        marked[1].kind = .warmup
        marked[0].kind = .working
        XCTAssertFalse(TrainingSetTemplate.canRemove(marked, at: 1, prescribedWorkingSets: 2))
        XCTAssertTrue(TrainingSetTemplate.canRemove(marked, at: 0, prescribedWorkingSets: 2))
        let log = TrainingExerciseLog(exercise: exercise(), sets: marked)
        let next = TrainingSetTemplate.next(previous: log, prescribedWorkingSets: 2)
        XCTAssertEqual(next.map(\.isAdditional), marked.map(\.isAdditional))
    }

    func testWarmupsAndAdvancedSetTypesPersistAndScaleWithWorkingLoad() {
        let exercise = exercise()
        let plan = TrainingPlan(payload: .init(formatVersion: 1, name: "Forza", days: [.init(id: "bench-day", name: "Bench", exercises: [exercise])]))
        var previous = TrainingSession(planID: plan.id, dayName: "Bench", calendarEventID: nil, start: Date(timeIntervalSince1970: 100),
            exercises: [TrainingExerciseLog(exercise: exercise, sets: [
                TrainingSet(number: 1, kg: 40, reps: 8, done: true, kind: .warmup),
                TrainingSet(number: 2, kg: 55, reps: 5, done: true, kind: .warmup),
                TrainingSet(number: 3, kg: 70, reps: 4, done: true, kind: .working),
                TrainingSet(number: 4, kg: 70, reps: 4, done: true, kind: .working, toFailure: true),
                TrainingSet(number: 5, kg: 60, reps: 8, done: true, kind: .backoff),
                TrainingSet(number: 6, kg: 20, reps: 12, done: true, kind: .dropSet)
            ])], dayID: "bench-day")
        previous.end = previous.start.addingTimeInterval(3600)
        var library = TrainingLibrary(plans: [plan], activePlanID: plan.id, sessions: [previous])
        var next = library.makeSession(plan: plan, day: plan.payload.days[0], eventID: nil, now: Date(timeIntervalSince1970: 10_000))
        XCTAssertEqual(next.exercises[0].sets.map(\.resolvedKind), [.warmup, .warmup, .working, .working, .backoff, .dropSet])
        XCTAssertTrue(next.exercises[0].sets[3].reachesFailure)
        XCTAssertTrue(next.exercises[0].sets.allSatisfy { !$0.done })
        for index in next.exercises[0].sets.indices where next.exercises[0].sets[index].resolvedKind == .working {
            next.exercises[0].sets[index].kg = 100
        }
        TrainingSetTemplate.rescaleWarmups(in: &next.exercises[0].sets, workingLoad: 100)
        XCTAssertEqual(next.exercises[0].sets[0].kg, 57.5)
        XCTAssertEqual(next.exercises[0].sets[1].kg, 77.5)
        library.sessions.append(next)
        XCTAssertNoThrow(try library.validate())
    }

    func testProgrammedCardioCompletesFromHealthWithoutAttentionThreshold() throws {
        let event = event()
        let workout = HealthWorkoutSummary(id: "health-cardio", start: event.start, end: event.start.addingTimeInterval(2700),
                                           type: "walk", durationSeconds: 2700, distanceKM: 3, activeCalories: nil)
        let merged = try XCTUnwrap(HealthReconciliation.merge(workouts: [workout], sleeps: [:], events: [event], data: AppData(), now: event.end.addingTimeInterval(60)))
        XCTAssertEqual(merged.records[event.id]?.status, .completed)
        XCTAssertEqual(merged.records[event.id]?.health?.id, workout.id)
        XCTAssertEqual(merged.records[event.id]?.cardio?.distanceKM, 3)
    }

    func testSleepFromHealthAutofillsAndRefreshesOnlyHealthDerivedValues() throws {
        let day = ISO8601DateFormatter().date(from: "2026-10-07T08:00:00+02:00")!
        let key = PivotDate.key(day)
        let first = HealthSleepSummary(start: day.addingTimeInterval(-8 * 3600), end: day, durationSeconds: 7 * 3600, interruptionSeconds: 600, awakenings: 2)
        var merged = try XCTUnwrap(HealthReconciliation.merge(workouts: [], sleeps: [key: first], events: [], data: AppData(), now: day))
        XCTAssertTrue(merged.checkIns[key]?.sleep?.importedFromHealth == true)
        XCTAssertEqual(merged.checkIns[key]?.wakeTime, day)
        let refreshed = HealthSleepSummary(start: day.addingTimeInterval(-9 * 3600), end: day.addingTimeInterval(300), durationSeconds: 8 * 3600, interruptionSeconds: nil, awakenings: nil)
        merged = try XCTUnwrap(HealthReconciliation.merge(workouts: [], sleeps: [key: refreshed], events: [], data: merged, now: refreshed.end))
        XCTAssertEqual(merged.checkIns[key]?.sleep?.durationSeconds, 8 * 3600)
        var manual = merged
        manual.checkIns[key]?.sleep = SleepRecord(bedtime: first.start, durationSeconds: 1234, importedFromHealth: false)
        XCTAssertNil(HealthReconciliation.merge(workouts: [], sleeps: [key: refreshed], events: [], data: manual, now: refreshed.end))
    }

    func testWorkoutGuideContains302NonPhotographicIllustrationsAndMatchesBench() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let guide = try WorkoutGuideCatalog.load(from: root.appendingPathComponent("Pivot/Resources/workout-guide.json"))
        XCTAssertEqual(guide.count, 302)
        let bench = try XCTUnwrap(WorkoutGuideCatalog.match(exercise(), catalogEntry: nil, in: guide))
        XCTAssertEqual(bench.slug, "bench-press")
        XCTAssertTrue(bench.imageURL()?.absoluteString.contains(WorkoutGuideCatalog.sourceRevision) == true)
        XCTAssertTrue(bench.imageURL()?.absoluteString.hasSuffix("/bench-press/frame-1.png") == true)
    }
}
