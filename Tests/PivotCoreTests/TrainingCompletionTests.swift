import XCTest
@testable import PivotCore

final class TrainingCompletionTests: XCTestCase {
    private func session(_ exercise: TrainingExercise, sets: [TrainingSet]) -> TrainingSession {
        .init(planID: UUID(), dayName: "Test", calendarEventID: nil, start: Date(), exercises: [.init(exercise: exercise, sets: sets)])
    }
    private var bench: TrainingExercise { .init(id: "bench", name: "Bench Press", sets: 2, reps: "6", restSeconds: 60, coachNotes: "") }
    private var plank: TrainingExercise { .init(id: "plank", name: "Plank", sets: 2, reps: "30 s", restSeconds: 60, coachNotes: "") }
    func testZeroIsAnExplicitSkipButEmptyHoldStaysUnresolved() throws {
        var s = session(plank, sets: [.init(number: 1), .init(number: 2, durationSeconds: 0)])
        XCTAssertEqual(TrainingCompletion.toggle(in: &s, exerciseIndex: 0, setIndex: 0), .invalid)
        XCTAssertEqual(TrainingCompletion.toggle(in: &s, exerciseIndex: 0, setIndex: 1), .skipped)
        XCTAssertFalse(s.exercises[0].sets[1].done); XCTAssertNil(s.rest)
        var library = TrainingLibrary(sessions: [s]); try library.validate()
        library = try JSONDecoder().decode(TrainingLibrary.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(library.sessions[0].exercises[0].sets[1].durationSeconds, 0)
        XCTAssertEqual(library.sessions[0].exercises[0].sets[1].skipped, true)
        XCTAssertTrue(TrainingReports.performed(in: TrainingReports.week(containing: s.start), library: library).isEmpty)
        s.end = s.start.addingTimeInterval(60)
        XCTAssertTrue(ExerciseProgress.calculate(exerciseID: plank.id, library: TrainingLibrary(sessions: [s])).performances.isEmpty)
    }
    func testSkippingNeedsNoLoadAndUndoPreservesInputs() throws {
        var s = session(bench, sets: [.init(number: 1, kg: 50), .init(number: 2)])
        TrainingCompletion.skipExercise(in: &s, at: 0, reason: "Poco tempo")
        try TrainingLibrary(sessions: [s]).validate()
        XCTAssertEqual(s.exercises[0].skipped, true); XCTAssertNil(s.exercises[0].sets[0].reps)
        TrainingCompletion.resumeExercise(in: &s, at: 0)
        XCTAssertEqual(s.exercises[0].sets[0].kg, 50); XCTAssertNil(s.exercises[0].skipReason)
    }
    func testPartialSkipKeepsPerformedWorkAndDoesNotSuggestSkippedLoad() throws {
        var s = session(bench, sets: [.init(number: 1, kg: 50, reps: 6, done: true), .init(number: 2, kg: 500, reps: 99)])
        TrainingCompletion.skipExercise(in: &s, at: 0)
        try TrainingLibrary(sessions: [s]).validate()
        XCTAssertNil(s.exercises[0].skipped); XCTAssertTrue(s.exercises[0].sets[0].done)
        XCTAssertEqual(s.exercises[0].sets[1].skipped, true)
        let next = TrainingSetTemplate.next(previous: s.exercises[0], prescribedWorkingSets: 2)
        XCTAssertEqual(next[0].kg, 50); XCTAssertNil(next[1].kg); XCTAssertNil(next[1].skipped)
    }
    func testBothZeroSidesSkipWithoutInventingWeightAndSingleZeroSidePreservesWork() {
        var ex = plank; ex.separateSides = true; ex.weightedHold = true
        var s = session(ex, sets: [.init(number: 1, leftSeconds: 0, rightSeconds: 0)])
        XCTAssertEqual(TrainingCompletion.toggle(in: &s, exerciseIndex: 0, setIndex: 0), .skipped)
        s.exercises[0].sets = [.init(number: 1, kg: 5, leftSeconds: 0, rightSeconds: 20)]
        XCTAssertEqual(TrainingCompletion.toggle(in: &s, exerciseIndex: 0, setIndex: 0), .performed)
        XCTAssertEqual(s.exercises[0].sets[0].holdTotal, 20)
    }
    func testOldBackupsDecodeWithoutNewFieldsAndInvalidContradictionIsRejected() throws {
        var s = session(bench, sets: [.init(number: 1, kg: 20, reps: 10, done: true)])
        let data = try JSONEncoder().encode(s)
        let old = try JSONDecoder().decode(TrainingSession.self, from: data)
        XCTAssertNil(old.exercises[0].skipped); XCTAssertNil(old.exercises[0].sets[0].skipped)
        s.exercises[0].sets[0].skipped = true
        XCTAssertThrowsError(try TrainingLibrary(sessions: [s]).validate())
    }
}
