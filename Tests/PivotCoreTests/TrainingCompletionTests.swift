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
    func testSkippedPlannedLoadCannotCorruptWarmupRatiosOrOverwriteSkippedInputs() {
        var s = session(bench, sets: [.init(number: 1, kg: 20, reps: 8, done: true, kind: .warmup),
                                     .init(number: 2, kg: 50, reps: 6, done: true),
                                     .init(number: 3, kg: 500)])
        TrainingCompletion.skipExercise(in: &s, at: 0)
        TrainingSetTemplate.rememberWarmupFractions(in: &s.exercises[0].sets)
        XCTAssertEqual(s.exercises[0].sets[0].loadFraction!, 0.4, accuracy: 0.001)
        let next = TrainingSetTemplate.next(previous: s.exercises[0], prescribedWorkingSets: 2)
        XCTAssertEqual(next[0].kg, 20)
        var skippedWarmup = [TrainingSet(number: 1, kg: 10, kind: .warmup, loadFraction: 0.5, skipped: true)]
        TrainingSetTemplate.rescaleWarmups(in: &skippedWarmup, workingLoad: 80)
        XCTAssertEqual(skippedWarmup[0].kg, 10)
    }

    func testSeriesTargetKeepsNumberedLoadAndRepetitionsDistinctFromDraftValues() throws {
        var exercise = bench
        exercise.reps = "S1: 6–8; S2: 4"
        exercise.coachNotes = "Carico prescritto: S1: 42,5; S2: 45 kg. Recupero non specificato."
        let log = TrainingExerciseLog(exercise: exercise, sets: [
            .init(number: 1, kind: .warmup, isAdditional: true),
            .init(number: 2, kg: 40, reps: 7, isAdditional: false),
            .init(number: 3, isAdditional: false),
            .init(number: 4, isAdditional: true)
        ])
        XCTAssertNil(TrainingSetEntry.target(for: 0, in: log))
        XCTAssertEqual(try XCTUnwrap(TrainingSetEntry.target(for: 1, in: log)).label, "6–8 rip. · 42,5 kg")
        XCTAssertEqual(TrainingSetEntry.target(for: 1, in: log)?.quickReps, [6, 7, 8])
        XCTAssertEqual(TrainingSetEntry.target(for: 2, in: log)?.label, "4 rip. · 45 kg")
        XCTAssertNil(TrainingSetEntry.target(for: 3, in: log))
        XCTAssertEqual(log.sets[1].kg, 40)
        XCTAssertNil(log.sets[2].kg)
    }

    func testTimedAndAmbiguousTargetsStayInTheirOwnUnits() {
        let hold = TrainingExerciseLog(exercise: plank, sets: [.init(number: 1)])
        XCTAssertEqual(TrainingSetEntry.target(for: 0, in: hold)?.label, "30 s")
        XCTAssertEqual(TrainingSetEntry.target(for: 0, in: hold)?.quickReps, [])
        var exercise = bench
        exercise.reps = "8 per lato"
        exercise.coachNotes = "Provare 50 kg"
        let log = TrainingExerciseLog(exercise: exercise, sets: [.init(number: 1)])
        XCTAssertEqual(TrainingSetEntry.target(for: 0, in: log)?.label, "8 per lato")
        XCTAssertEqual(TrainingSetEntry.target(for: 0, in: log)?.quickReps, [])
    }

    func testPreviousComparableSeriesDoesNotShiftWhenASetWasSkipped() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var older = session(bench, sets: [
            .init(number: 1, kg: 25, reps: 6, done: true),
            .init(number: 2, kg: 26, reps: 7, done: true)
        ])
        older.start = now.addingTimeInterval(-3600); older.end = now.addingTimeInterval(-3000)
        var recent = session(bench, sets: [
            .init(number: 1, kg: 15, reps: 6, done: true, kind: .warmup),
            .init(number: 2, skipped: true),
            .init(number: 3, kg: 30, reps: 8, done: true)
        ])
        recent.start = now.addingTimeInterval(-1800); recent.end = now.addingTimeInterval(-1200)
        var current = session(bench, sets: [.init(number: 1, note: "Nota locale"), .init(number: 2)])
        current.start = now
        let matches = TrainingSetEntry.previousSets(for: current.exercises[0], session: current,
                                                    library: TrainingLibrary(sessions: [recent, older]))
        let first = try XCTUnwrap(matches[current.exercises[0].sets[0].id])
        XCTAssertEqual(first.kg, 25)
        XCTAssertEqual(matches[current.exercises[0].sets[1].id]?.kg, 30)
        TrainingSetEntry.usePrevious(first, at: 0, in: &current.exercises[0])
        XCTAssertEqual(current.exercises[0].sets[0].kg, 25)
        XCTAssertEqual(current.exercises[0].sets[0].note, "Nota locale")
        XCTAssertNil(current.exercises[0].sets[1].kg)
        XCTAssertFalse(current.exercises[0].sets[0].done)
        XCTAssertNil(current.rest)
        XCTAssertEqual(TrainingCompletion.toggle(in: &current, exerciseIndex: 0, setIndex: 0, now: now), .performed)
        XCTAssertEqual(current.rest?.setID, current.exercises[0].sets[0].id)
    }

    func testSetNotesSurviveBackupsButDoNotBecomePartOfTheNextWorkout() throws {
        let recorded = TrainingSet(number: 1, kg: 35, reps: 6, done: true, note: "Presa diversa")
        var data = AppData()
        data.training = TrainingLibrary(sessions: [session(bench, sets: [recorded, .init(number: 2)])])
        let restored = try BackupCodec.decode(BackupCodec.encodeCompact(data))
        let log = try XCTUnwrap(restored.training?.sessions.first?.exercises.first)
        XCTAssertEqual(log.sets[0].note, "Presa diversa")
        XCTAssertNil(log.sets[1].note)
        XCTAssertNil(TrainingSetTemplate.next(previous: log, prescribedWorkingSets: 2)[0].note)
        XCTAssertNil(TrainingSetEntry.note("  \n "))
        XCTAssertEqual(TrainingSetEntry.note(String(repeating: "a", count: 501))?.count, 500)
        data.training?.sessions[0].exercises[0].sets[0].note = String(repeating: "a", count: 501)
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encodeCompact(data)))
    }
}
