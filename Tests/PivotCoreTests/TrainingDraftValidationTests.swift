import XCTest
@testable import PivotCore

final class TrainingDraftValidationTests: XCTestCase {
    private func session(done: Bool = true) -> TrainingSession {
        let exercise = TrainingExercise(id: "draft-test", name: "Movimento TEST", sets: 1, reps: "6", restSeconds: 60, coachNotes: "")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return .init(planID: UUID(), dayName: "TEST", calendarEventID: nil, start: date, end: date.addingTimeInterval(600),
                     exercises: [.init(exercise: exercise, sets: [.init(number: 1, kg: 40, reps: 6, done: done)])])
    }
    func testReplacingCompletedLoadWaitsForValidValueWithoutMutatingSavedSnapshot() {
        let saved = session(); var draft = saved
        draft.exercises[0].sets[0].kg = nil
        XCTAssertFalse(TrainingDraftValidation.canAutosave(draft))
        XCTAssertEqual(saved.exercises[0].sets[0].kg, 40)
        XCTAssertTrue(saved.exercises[0].sets[0].done)
        draft.exercises[0].sets[0].kg = 50
        XCTAssertTrue(TrainingDraftValidation.canAutosave(draft))
        XCTAssertEqual(draft.end, saved.end)
        XCTAssertNil(draft.rest)
    }
    func testReplacingCompletedRepetitionsWaitsForInputAndKeepsCompletion() {
        var draft = session(); draft.exercises[0].sets[0].reps = nil
        XCTAssertFalse(TrainingDraftValidation.canAutosave(draft))
        draft.exercises[0].sets[0].reps = 8
        XCTAssertTrue(TrainingDraftValidation.canAutosave(draft))
        XCTAssertTrue(draft.exercises[0].sets[0].done)
    }
    func testUnconfirmedBlankInputsRemainSaveableWithoutInventingWork() {
        var draft = session(done: false)
        draft.exercises[0].sets[0].kg = nil; draft.exercises[0].sets[0].reps = nil
        XCTAssertTrue(TrainingDraftValidation.canAutosave(draft))
        XCTAssertFalse(draft.exercises[0].sets[0].done)
    }
    func testDraftUsesExistingValidationAndCannotSaveInvalidValuesOrTiming() {
        var draft = session(); draft.exercises[0].sets[0].kg = -1
        XCTAssertFalse(TrainingDraftValidation.canAutosave(draft))
        draft.exercises[0].sets[0].kg = .infinity
        XCTAssertFalse(TrainingDraftValidation.canAutosave(draft))
        draft.exercises[0].sets[0].kg = 40; draft.end = draft.start.addingTimeInterval(-1)
        XCTAssertFalse(TrainingDraftValidation.canAutosave(draft))
    }
}
