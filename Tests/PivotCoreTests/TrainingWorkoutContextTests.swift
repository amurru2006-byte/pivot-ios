import XCTest
@testable import PivotCore

final class TrainingWorkoutContextTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10000)
    private func workout() -> TrainingSession {
        let bench = TrainingExercise(id: "bench", name: "Bench Press", sets: 2, reps: "4–6", restSeconds: 90, coachNotes: "")
        let crunch = TrainingExercise(id: "crunch", name: "Cable Crunch", sets: 2, reps: "10–12", restSeconds: 60, coachNotes: "")
        return .init(planID: UUID(), dayName: "Squat", calendarEventID: nil, start: now, exercises: [
            .init(exercise: bench, sets: [.init(number: 1, kind: .warmup), .init(number: 2), .init(number: 3)]),
            .init(exercise: crunch, sets: [.init(number: 1, kg: 20, reps: 12), .init(number: 2, kg: 20, reps: 12)])])
    }
    func testWorkingNumberDoesNotCountWarmup() {
        let session = workout()
        let first = TrainingWorkoutContext.next(in: session)
        XCTAssertEqual(first?.set.resolvedKind, .warmup)
        let working = TrainingWorkoutContext.next(in: session, focusedSetID: session.exercises[0].sets[1].id)
        XCTAssertEqual(working?.workingNumber, 1)
        XCTAssertEqual(working?.prescription, "Serie 1 di 2 · 4–6 reps")
    }
    func testRecoveryAtLastExerciseContinuesLocallyBeforeEarlierUnfinishedWork() {
        var session = workout()
        TrainingCompletion.toggle(in: &session, exerciseIndex: 1, setIndex: 0, now: now)
        XCTAssertEqual(TrainingWorkoutContext.restOrigin(in: session)?.exercise.name, "Cable Crunch")
        XCTAssertEqual(TrainingWorkoutContext.next(in: session)?.set.id, session.exercises[1].sets[1].id)
        XCTAssertEqual(TrainingWorkoutContext.next(in: session)?.workingNumber, 2)
    }
    func testExplicitFocusWinsAndResolvedFocusCannotReopenWork() {
        var session = workout()
        TrainingCompletion.toggle(in: &session, exerciseIndex: 1, setIndex: 0, now: now)
        XCTAssertEqual(TrainingWorkoutContext.next(in: session, focusedSetID: session.exercises[0].sets[1].id)?.exercise.id, "bench")
        XCTAssertEqual(TrainingWorkoutContext.next(in: session, focusedSetID: session.exercises[1].sets[0].id)?.set.id, session.exercises[1].sets[1].id)
    }
    func testLastRecoveryHasAnOriginButNoInventedNextSetAndSurvivesBackup() throws {
        var session = workout()
        TrainingCompletion.skipExercise(in: &session, at: 0)
        TrainingCompletion.toggle(in: &session, exerciseIndex: 1, setIndex: 0, now: now)
        TrainingCompletion.toggle(in: &session, exerciseIndex: 1, setIndex: 1, now: now.addingTimeInterval(75))
        session.rest?.togglePause(now: now.addingTimeInterval(80))
        session = try JSONDecoder().decode(TrainingSession.self, from: JSONEncoder().encode(session))
        XCTAssertNil(TrainingWorkoutContext.next(in: session))
        XCTAssertEqual(TrainingWorkoutContext.restOrigin(in: session)?.set.number, 2)
        XCTAssertEqual(session.exercises[1].sets[0].actualRestSeconds, 75)
        XCTAssertEqual(session.rest?.remaining(at: now.addingTimeInterval(500)), 55)
        TrainingCompletion.finishRest(in: &session, now: now.addingTimeInterval(90))
        XCTAssertEqual(session.exercises[1].sets[1].actualRestSeconds, 15)
        XCTAssertNil(session.rest)
    }
    func testSkippedSetsAreNeverSuggestedAndClosedWorkoutHasNoNextSet() {
        var session = workout()
        session.exercises[0].sets[0].skipped = true
        XCTAssertEqual(TrainingWorkoutContext.next(in: session)?.set.id, session.exercises[0].sets[1].id)
        TrainingCompletion.skipExercise(in: &session, at: 0)
        XCTAssertEqual(TrainingWorkoutContext.next(in: session)?.exercise.id, "crunch")
        session.end = now.addingTimeInterval(300)
        XCTAssertNil(TrainingWorkoutContext.next(in: session))
        TrainingCompletion.toggle(in: &session, exerciseIndex: 1, setIndex: 0, now: now.addingTimeInterval(400))
        XCTAssertNil(session.rest, "Editing history must not start a live recovery")
    }
    func testResetAndPauseDoNotEraseActualElapsedRest() {
        var session = workout()
        TrainingCompletion.toggle(in: &session, exerciseIndex: 1, setIndex: 0, now: now)
        session.rest?.togglePause(now: now.addingTimeInterval(20))
        session.rest?.resetCountdown(now: now.addingTimeInterval(90))
        TrainingCompletion.toggle(in: &session, exerciseIndex: 1, setIndex: 1, now: now.addingTimeInterval(110))
        XCTAssertEqual(session.exercises[1].sets[0].actualRestSeconds, 110)
        XCTAssertEqual(session.rest?.setID, session.exercises[1].sets[1].id)
    }
}
