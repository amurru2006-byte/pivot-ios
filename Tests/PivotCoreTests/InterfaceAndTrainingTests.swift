import XCTest
@testable import PivotCore

final class InterfaceAndTrainingTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func event() -> CalendarItem {
        CalendarItem(id: "autofill", eventIdentifier: "autofill", calendarIdentifier: "test", calendarTitle: "Studio", title: "Studio", start: date("2026-10-07T10:00:00+02:00"), end: date("2026-10-07T11:00:00+02:00"), location: "", notes: "", colorHex: "#FFFFFF", isAllDay: false, writable: true, kind: .study)
    }
    private func exercise(_ id: String = "bench") -> TrainingExercise {
        TrainingExercise(id: id, name: "Panca piana", sets: 2, reps: "8", restSeconds: 90, coachNotes: "")
    }
    private func library() -> TrainingLibrary {
        let plan = TrainingPlan(payload: .init(formatVersion: 1, name: "Prima", days: [.init(id: "a", name: "A", exercises: [exercise()])]), document: nil)
        return TrainingLibrary(plans: [plan], activePlanID: plan.id)
    }
    func testFlagFillsExpectedTimesButNotSubjectiveOrFinancialData() {
        let event = event(); var record = EventRecord(id: event.id, snapshot: event)
        EventAutofill.complete(&record, event: event)
        XCTAssertEqual(record.status, .completed); XCTAssertEqual(record.actualStart, event.start)
        XCTAssertEqual(record.actualEnd, event.end); XCTAssertEqual(record.activeMinutes, 60)
        XCTAssertEqual(record.timingFromCalendar, true); XCTAssertNil(record.energy); XCTAssertNil(record.fatigue)
        XCTAssertNil(record.incomeID); XCTAssertNil(record.health); XCTAssertNil(record.healthSleep)
    }
    func testReopenedAutofilledEventKeepsSavedCorrectionsThroughBackup() throws {
        let event = event(); var record = EventRecord(id: event.id, snapshot: event)
        EventAutofill.complete(&record, event: event)
        record.actualEnd = event.end.addingTimeInterval(1800); record.activeMinutes = 70
        record.notes = "Pausa e correzione personale"; record.energy = 4; record.timingFromCalendar = false
        var data = AppData(); data.records[event.id] = record
        let reopened = try XCTUnwrap(BackupCodec.decode(BackupCodec.encode(data)).records[event.id])
        XCTAssertEqual(reopened.actualEnd, record.actualEnd); XCTAssertEqual(reopened.activeMinutes, 70)
        XCTAssertEqual(reopened.notes, record.notes); XCTAssertEqual(reopened.energy, 4)
        // Even another explicit autofill preserves already supplied nonzero duration and endpoints.
        var again = reopened; EventAutofill.complete(&again, event: event)
        XCTAssertEqual(again.actualEnd, reopened.actualEnd); XCTAssertEqual(again.activeMinutes, 70)
        XCTAssertEqual(again.energy, 4); XCTAssertEqual(again.timingFromCalendar, false)
    }
    func testAutofillDoesNotMixActualStartWithGuessedEndOrGuessAllDayDuration() {
        var event = event(); var record = EventRecord(id: event.id, snapshot: event)
        record.actualStart = event.start.addingTimeInterval(1200)
        EventAutofill.complete(&record, event: event); XCTAssertNil(record.actualEnd); XCTAssertEqual(record.activeMinutes, 0)
        event.isAllDay = true; record = EventRecord(id: event.id, snapshot: event)
        EventAutofill.complete(&record, event: event); XCTAssertNil(record.actualStart); XCTAssertEqual(record.activeMinutes, 0)
    }
    func testMealAsPlannedKeepsPreviousException() {
        var event = event(); event.kind = .meal
        var record = EventRecord(id: event.id, snapshot: event)
        EventAutofill.complete(&record, event: event); XCTAssertEqual(record.followedMeal, true)
        record.followedMeal = false; EventAutofill.complete(&record, event: event); XCTAssertEqual(record.followedMeal, false)
    }
    func testHistoricalReferenceIsMeanOfWeeklyMeansNotAllSamples() {
        var data = AppData()
        data.checkIns["2026-09-28"] = .init(id: "2026-09-28", energyMorning: 2, energyEvening: 2)
        data.checkIns["2026-09-29"] = .init(id: "2026-09-29", energyMorning: 2, energyEvening: 2)
        data.checkIns["2026-09-21"] = .init(id: "2026-09-21", energyMorning: 10)
        data.checkIns["2026-10-06"] = .init(id: "2026-10-06", energyMorning: 0)
        data.checkIns["2026-09-01"] = .init(id: "2026-09-01", energyMorning: 0)
        let result = RatingReferences.historical(.energy, before: date("2026-10-07T12:00:00+02:00"), data: data)
        XCTAssertEqual(result.mean, 6); XCTAssertEqual(result.weeksWithData, 2); XCTAssertEqual(result.samples, 5)
    }
    func testMissingRatingsAreNotZerosAndTargetsAreSeparate() {
        var data = AppData(); data.checkIns["2026-09-28"] = .init(id: "2026-09-28")
        XCTAssertNil(RatingReferences.historical(.energy, before: event().start, data: data).mean)
        XCTAssertEqual(RatingMetric.energy.target(in: data.settings), 7)
        data.settings.ratingTargets = ["energy": 9, "fatigue": -1]
        XCTAssertEqual(RatingMetric.energy.target(in: data.settings), 9); XCTAssertNil(RatingMetric.fatigue.target(in: data.settings))
        XCTAssertNil(data.checkIns["2026-09-28"]?.energyMorning)
    }
    func testWeeklyReferencesCrossYearAndDST() {
        XCTAssertEqual(RatingReferences.week(containing: date("2027-01-01T12:00:00+01:00")).start, date("2026-12-28T00:00:00+01:00"))
        XCTAssertEqual(RatingReferences.week(containing: date("2026-10-25T12:00:00+01:00")).start, date("2026-10-19T00:00:00+02:00"))
    }
    func testStatisticsExcludePrefilledUnfinishedAndOtherVariants() {
        var library = library(); let plan = library.plans[0]
        var session = library.makeSession(plan: plan, day: plan.payload.days[0], eventID: nil, now: event().start)
        session.exercises[0].sets = [.init(number: 1, kg: 60, reps: 8, done: true), .init(number: 2, kg: 100, reps: 10, done: false)]
        library.sessions = [session]
        XCTAssertTrue(ExerciseProgress.calculate(exerciseID: "bench", library: library).performances.isEmpty)
        let live = ExerciseProgress.calculate(exerciseID: "bench", library: library, current: session)
        XCTAssertEqual(live.bestVolume, 480); XCTAssertEqual(live.bestLoad, 60); XCTAssertEqual(live.estimatedMax!, 76, accuracy: 0.001)
        session.end = session.start.addingTimeInterval(3600); library.sessions = [session]
        XCTAssertEqual(ExerciseProgress.calculate(exerciseID: "bench", library: library).performances.count, 1)
        XCTAssertTrue(ExerciseProgress.calculate(exerciseID: "incline", library: library).performances.isEmpty)
    }
    func testEstimatedMaxUsesOnlyValidShortSetsAndSingleRepActualLoad() {
        XCTAssertEqual(ExerciseProgress.estimatedMax(.init(number: 1, kg: 100, reps: 1, done: true)), 100)
        XCTAssertNil(ExerciseProgress.estimatedMax(.init(number: 1, kg: 60, reps: 11, done: true)))
        XCTAssertNil(ExerciseProgress.estimatedMax(.init(number: 1, kg: 0, reps: 10, done: true)))
        XCTAssertNil(ExerciseProgress.estimatedMax(.init(number: 1, kg: .infinity, reps: 8, done: true)))
    }
    func testPlanRevisionPreservesHistoricalPrescriptionAndStableExerciseID() throws {
        var library = library(); let plan = library.plans[0]
        let session = library.makeSession(plan: plan, day: plan.payload.days[0], eventID: nil)
        library.sessions = [session]; var changed = plan.payload; changed.days[0].exercises[0].sets = 4
        try TrainingEdits.revise(planID: plan.id, payload: changed, note: "Coach", library: &library)
        XCTAssertEqual(library.plans[0].revisions?.first?.payload, plan.payload)
        XCTAssertEqual(library.sessions[0].exercises[0].exercise.sets, 2)
        XCTAssertEqual(library.plans[0].payload.days[0].exercises[0].id, "bench")
        XCTAssertEqual(library.makeSession(plan: library.plans[0], day: changed.days[0], eventID: nil).exercises[0].sets.count, 4)
        try TrainingEdits.revise(planID: plan.id, payload: changed, note: "No change", library: &library)
        XCTAssertEqual(library.plans[0].revisions?.count, 1)
    }
    func testInvalidPlanChangeDoesNotMutateAnything() {
        var library = library(); let original = library.plans[0].payload
        var invalid = original; invalid.days[0].exercises = []
        XCTAssertThrowsError(try TrainingEdits.revise(planID: library.plans[0].id, payload: invalid, note: "", library: &library))
        XCTAssertEqual(library.plans[0].payload, original); XCTAssertNil(library.plans[0].revisions)
    }
    func testReplacementAndExtraAffectOnlySessionAndNeverReassignCompletedSets() throws {
        let library = library(), plan = library.plans[0]
        var session = library.makeSession(plan: plan, day: plan.payload.days[0], eventID: nil)
        try TrainingEdits.replace(in: &session, exerciseID: "bench", with: exercise("row"), library: library)
        XCTAssertEqual(session.exercises[0].id, "row"); XCTAssertEqual(plan.payload.days[0].exercises[0].id, "bench")
        session.exercises[0].sets[0] = .init(number: 1, kg: 30, reps: 8, done: true)
        XCTAssertThrowsError(try TrainingEdits.replace(in: &session, exerciseID: "row", with: exercise("squat"), library: library))
        XCTAssertEqual(session.exercises[0].id, "row"); XCTAssertTrue(session.exercises[0].sets[0].done)
        try TrainingEdits.add(to: &session, exercise: exercise("squat"), library: library)
        XCTAssertEqual(session.exercises.count, 2); XCTAssertFalse(session.exercises[1].sets[0].done)
        XCTAssertThrowsError(try TrainingEdits.add(to: &session, exercise: exercise("squat"), library: library))
    }
    func testManualPlanAndRevisionsSurviveBackupWithoutPDF() throws {
        var data = AppData(); var library = library(); var changed = library.plans[0].payload
        changed.name = "Coach aggiornamento"
        try TrainingEdits.revise(planID: library.plans[0].id, payload: changed, note: "Revisione", library: &library)
        data.training = library
        let reopened = try XCTUnwrap(BackupCodec.decode(BackupCodec.encode(data)).training)
        XCTAssertNil(reopened.plans[0].document); XCTAssertEqual(reopened.plans[0].revisions?.count, 1)
        XCTAssertEqual(reopened.plans[0].payload.name, changed.name); XCTAssertTrue(StudyFiles.documents(in: data).isEmpty)
    }
    func testOfflineCatalogHasMusclesUniqueIDsAndNoWrongBenchVariantImage() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let entries = try ExerciseCatalog.load(from: root.appendingPathComponent("Pivot/Resources/exercises.json"))
        XCTAssertEqual(entries.count, 876)
        let bench = try XCTUnwrap(entries.first { $0.id == "Barbell_Bench_Press_-_Medium_Grip" })
        XCTAssertEqual(bench.primaryMuscles, ["chest"]); XCTAssertEqual(bench.secondaryMuscles, ["shoulders", "triceps"])
        XCTAssertEqual(ExerciseCatalog.match(exercise(), in: entries)?.id, nil) // no fuzzy identity/statistics merging
        XCTAssertTrue(ExerciseCatalog.hasBenchIllustration(exercise()))
        var incline = exercise(); incline.name = "Panca inclinata"; XCTAssertFalse(ExerciseCatalog.hasBenchIllustration(incline))
        incline.catalogID = "Barbell_Incline_Bench_Press_-_Medium_Grip"; incline.name = "Panca piana"; XCTAssertFalse(ExerciseCatalog.hasBenchIllustration(incline))
    }
}
