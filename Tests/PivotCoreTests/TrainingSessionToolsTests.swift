import XCTest
@testable import PivotCore

final class TrainingSessionToolsTests: XCTestCase {
    private let date = ISO8601DateFormatter().date(from: "2026-10-07T20:00:00+02:00")!
    private func exercise(_ name: String = "Bench Press") -> TrainingExercise {
        TrainingExercise(id: "exercise", name: name, sets: 2, reps: "8", restSeconds: 120, coachNotes: "")
    }
    func testRestSurvivesPauseAndSerializationWithoutLosingElapsed() throws {
        var rest = TrainingRest(exerciseID: "exercise", setID: UUID(), seconds: 120, now: date)
        rest.togglePause(now: date.addingTimeInterval(30))
        XCTAssertEqual(rest.remaining(at: date.addingTimeInterval(90)), 90)
        XCTAssertEqual(rest.elapsed(at: date.addingTimeInterval(90)), 90)
        rest = try JSONDecoder().decode(TrainingRest.self, from: JSONEncoder().encode(rest))
        rest.togglePause(now: date.addingTimeInterval(100))
        XCTAssertEqual(rest.remaining(at: date.addingTimeInterval(110)), 80)
        XCTAssertEqual(rest.elapsed(at: date.addingTimeInterval(110)), 110)
        XCTAssertEqual(rest.remaining(at: date.addingTimeInterval(500)), 0)
    }
    func testIsometryRequiresBothSidesButNoWeightUnlessSelected() {
        var ex = exercise("Copenhagen Plank"); ex.separateSides = true
        var set = TrainingSet(number: 1, leftSeconds: 25, rightSeconds: 25)
        XCTAssertTrue(set.canComplete(ex))
        set.rightSeconds = nil; XCTAssertFalse(set.canComplete(ex))
        set.rightSeconds = 25; ex.weightedHold = true; XCTAssertFalse(set.canComplete(ex))
        set.kg = 0; XCTAssertTrue(set.canComplete(ex))
    }
    func testResetOnlyRestartsCountdownAndKeepsRealElapsedRest() {
        var rest = TrainingRest(exerciseID: "exercise", setID: UUID(), seconds: 120, now: date)
        rest.togglePause(now: date.addingTimeInterval(30))
        rest.resetCountdown(now: date.addingTimeInterval(90))
        XCTAssertNil(rest.remainingWhenPaused)
        XCTAssertEqual(rest.remaining(at: date.addingTimeInterval(100)), 110)
        XCTAssertEqual(rest.elapsed(at: date.addingTimeInterval(100)), 100)
        XCTAssertEqual(rest.startedAt, date)
    }
    func testLegacyCopenhagenUsesPersonalTipAndPreservesOriginal() throws {
        let ex = exercise("Copenhagen Plank")
        let log = TrainingExerciseLog(exercise: ex, sets: [.init(number: 1, kg: 25, reps: 2, done: true)])
        let session = TrainingSession(planID: UUID(), dayName: "A", calendarEventID: nil, start: date, end: date.addingTimeInterval(100), exercises: [log])
        var library = TrainingLibrary(sessions: [session], tips: [ex.id: "i kg sono secondi di isometria"])
        try library.validate()
        XCTAssertTrue(TrainingIsometry.migrate(&library))
        let result = library.sessions[0].exercises[0]
        XCTAssertEqual(result.sets[0].leftSeconds, 25); XCTAssertEqual(result.sets[0].rightSeconds, 25)
        XCTAssertNil(result.sets[0].kg); XCTAssertEqual(result.sets[0].legacyKG, 25); XCTAssertEqual(result.sets[0].legacyReps, 2)
        try library.validate()
        XCTAssertFalse(TrainingIsometry.migrate(&library))
        XCTAssertTrue(TrainingReports.performance(result.sets[0], exercise: result.exercise).contains("Sx 25 s / Dx 25 s"))
    }
    func testOtherExerciseOrMissingExplicitMarkerIsNeverConverted() {
        let ex = exercise("Plank")
        let log = TrainingExerciseLog(exercise: ex, sets: [.init(number: 1, kg: 25, reps: 2, done: true)])
        let session = TrainingSession(planID: UUID(), dayName: "A", calendarEventID: nil, start: date, exercises: [log])
        var library = TrainingLibrary(sessions: [session], tips: [ex.id: "i kg sono secondi di isometria"])
        XCTAssertFalse(TrainingIsometry.migrate(&library)); XCTAssertEqual(library.sessions[0].exercises[0].sets[0].kg, 25)
        library.sessions[0].exercises[0].exercise.name = "Copenhagen Plank"; library.tips = [:]
        XCTAssertFalse(TrainingIsometry.migrate(&library))
    }
    func testNextSessionRemembersSideDurationsAndRestButNotCompletion() {
        let ex = exercise("Copenhagen Plank")
        let old = TrainingExerciseLog(exercise: ex, sets: [.init(number: 1, done: true, durationSeconds: nil, leftSeconds: 25, rightSeconds: 30, restSeconds: 45, actualRestSeconds: 40)])
        let next = TrainingSetTemplate.next(previous: old, prescribedWorkingSets: 1)[0]
        XCTAssertEqual(next.leftSeconds, 25); XCTAssertEqual(next.rightSeconds, 30); XCTAssertEqual(next.restSeconds, 45)
        XCTAssertNil(next.actualRestSeconds); XCTAssertNil(next.completedAt); XCTAssertFalse(next.done)
    }
    func testWeeklyReportOnlyIncludesWorkActuallyPerformedAndExcludesNextMonday() {
        let week = TrainingReports.week(containing: date)
        let ex = exercise()
        let done = TrainingExerciseLog(exercise: ex, sets: [.init(number: 1, kg: 50, reps: 8, done: true)])
        var first = TrainingSession(planID: UUID(), dayName: "A", calendarEventID: nil, start: week.start, exercises: [done])
        var second = first; second.id = UUID(); second.start = date
        var empty = first; empty.id = UUID(); empty.exercises[0].sets[0].done = false
        var monday = first; monday.id = UUID(); monday.start = week.end
        first.end = first.start.addingTimeInterval(3600)
        let library = TrainingLibrary(sessions: [monday, empty, second, first])
        let report = TrainingReports.performed(in: week, library: library)
        XCTAssertEqual(report.map(\.id), [first.id, second.id])
        XCTAssertEqual(PivotDate.key(week.start), "2026-10-05")
    }
    func testDurationStatisticsHaveNoEstimatedMaxOrRepVolume() {
        var ex = exercise("Plank"); ex.weightedHold = true
        let log = TrainingExerciseLog(exercise: ex, sets: [.init(number: 1, kg: 10, done: true, durationSeconds: 30)])
        let session = TrainingSession(planID: UUID(), dayName: "A", calendarEventID: nil, start: date, end: date.addingTimeInterval(60), exercises: [log])
        let progress = ExerciseProgress.calculate(exerciseID: ex.id, library: TrainingLibrary(sessions: [session]))
        XCTAssertEqual(progress.bestHold, 30); XCTAssertNil(progress.estimatedMax); XCTAssertEqual(progress.bestVolume, 0)
        XCTAssertNil(ExerciseProgress.estimatedMax(log.sets[0]))
    }
    func testAmbiguousTechniqueNeverGetsDifferentExerciseGuide() {
        XCTAssertNil(ExerciseTechnique.forExercise(exercise("Lunge"), catalog: nil))
        XCTAssertNotNil(ExerciseTechnique.forExercise(exercise("Bench Press"), catalog: nil))
        XCTAssertFalse(exercise("Plank with dumbbell row").usesDuration)
    }
}
