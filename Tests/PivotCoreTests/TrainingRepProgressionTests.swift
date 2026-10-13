import XCTest
@testable import PivotCore

final class TrainingRepProgressionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_000_000)
    private var exercise: TrainingExercise {
        .init(id: "rep-test", name: "Movimento TEST", sets: 3, reps: "6–8", restSeconds: 60, coachNotes: "Prescrizione TEST", catalogID: "rep-variant")
    }
    private func session(_ reps: [Int] = [8, 8, 8], offset: Double = 0, phase: TrainingPhase? = .loading, finished: Bool = true) -> TrainingSession {
        let sets = reps.enumerated().map { index, reps in
            TrainingSet(number: index + 1, kg: 40, reps: reps, done: true, kind: .working, isAdditional: false)
        }
        let start = now.addingTimeInterval(offset)
        return .init(planID: UUID(), dayName: "Giornata TEST", start: start,
                     end: finished ? start.addingTimeInterval(600) : nil,
                     exercises: [.init(exercise: exercise, sets: sets)], updatedAt: start, phase: phase)
    }
    private func result(_ sessions: [TrainingSession], exercise: TrainingExercise? = nil, current: TrainingSession? = nil) -> TrainingRepProgression {
        TrainingRepProgression.calculate(exercise: exercise ?? self.exercise, library: .init(sessions: sessions), current: current)
    }
    func testParsesOnlyExplicitNumericTargets() {
        for value in ["6", "6 reps", "6 ripetizioni"] {
            XCTAssertEqual(TrainingRepRange(value)?.lower, 6); XCTAssertEqual(TrainingRepRange(value)?.upper, 6)
        }
        for value in ["6-8", "6–8", "6 — 8", " 6 - 8 reps ", "6–8 ripetizioni"] {
            XCTAssertEqual(TrainingRepRange(value)?.lower, 6); XCTAssertEqual(TrainingRepRange(value)?.upper, 8)
        }
        XCTAssertEqual(TrainingRepRange("1000")?.upper, 1000)
    }
    func testDoesNotGuessTempoPyramidsSidesOrUnboundedTargets() {
        for value in ["", "0", "8-6", "-8", "6+", "AMRAP", "max", "6/8/10", "3 × 8", "8 per lato", "30 s", "6–8 @ RPE 8", "6.5", "1001", String(repeating: "1", count: 81)] {
            XCTAssertNil(TrainingRepRange(value), value)
        }
    }
    func testUpperRangeRequiresEveryPrescribedSet() {
        let value = result([session()]).latest
        XCTAssertEqual(value?.status, .atUpper); XCTAssertEqual(value?.completedCount, 3); XCTAssertEqual(value?.upperCount, 3)
        XCTAssertEqual(value?.totalReps, 24); XCTAssertNil(result([session()]).comparison)
    }
    func testMixedRepetitionsDistinguishMinimumFromUpperRange() {
        XCTAssertEqual(result([session([8, 7, 6])]).latest?.status, .inRange)
        XCTAssertEqual(result([session([8, 8, 5])]).latest?.status, .belowTarget)
        XCTAssertEqual(result([session([9, 10, 8])]).latest?.status, .atUpper)
    }
    func testFixedTargetUsesTheRecordedPrescriptionNotTheCurrentPlan() {
        var saved = session([6, 6, 6]); saved.exercises[0].exercise.reps = "6"
        let value = result([saved]).latest
        XCTAssertEqual(value?.target, "6"); XCTAssertEqual(value?.range?.upper, 6); XCTAssertEqual(value?.status, .atUpper)
        XCTAssertEqual(exercise.reps, "6–8")
    }
    func testPrefilledButUnconfirmedSetsAreNotResults() {
        var saved = session()
        for index in saved.exercises[0].sets.indices { saved.exercises[0].sets[index].done = false }
        let value = result([saved]).latest
        XCTAssertEqual(value?.status, .incomplete); XCTAssertEqual(value?.completedCount, 0); XCTAssertEqual(value?.totalReps, 0)
    }
    func testWarmupsAndExtrasCannotReplaceMissingPrescribedWork() {
        var saved = session()
        saved.exercises[0].sets[1].done = false
        saved.exercises[0].sets.append(.init(number: 4, kg: 100, reps: 20, done: true, kind: .warmup, isAdditional: true))
        saved.exercises[0].sets.append(.init(number: 5, kg: 100, reps: 20, done: true, kind: .working, isAdditional: true))
        let value = result([saved]).latest
        XCTAssertEqual(value?.status, .incomplete); XCTAssertEqual(value?.completedCount, 2); XCTAssertEqual(value?.totalReps, 16)
    }
    func testLegacyOriginsKeepOnlyThePrescribedNonWarmups() {
        var saved = session()
        for index in saved.exercises[0].sets.indices { saved.exercises[0].sets[index].isAdditional = nil }
        saved.exercises[0].sets.insert(.init(number: 4, kg: 20, reps: 20, done: true, kind: .warmup), at: 0)
        saved.exercises[0].sets.append(.init(number: 5, kg: 80, reps: 20, done: true, kind: .working))
        let value = result([saved]).latest
        XCTAssertEqual(value?.status, .atUpper); XCTAssertEqual(value?.completedCount, 3); XCTAssertEqual(value?.totalReps, 24)
    }
    func testSkippedSeriesAndMissingRowsRemainIncomplete() {
        var saved = session(); saved.exercises[0].sets[1].done = false; saved.exercises[0].sets[1].skipped = true
        XCTAssertEqual(result([saved]).latest?.status, .incomplete)
        XCTAssertEqual(result([session([8, 8])]).latest?.status, .incomplete)
        var extraRequired = session(); extraRequired.exercises[0].sets.append(.init(number: 4, kg: 40, reps: 8, done: true, isAdditional: false))
        XCTAssertEqual(result([extraRequired]).latest?.status, .incomplete)
    }
    func testSkippedExerciseIsNotACompleteGoal() {
        var saved = session(); saved.exercises[0].skipped = true
        for index in saved.exercises[0].sets.indices { saved.exercises[0].sets[index].done = false }
        XCTAssertEqual(result([saved]).latest?.status, .skipped)
    }
    func testOngoingSessionRemainsPartialAndReplacesItsPersistedCopy() {
        let old = session([6, 6, 6])
        var current = session(offset: 86400, finished: false)
        let persisted = current; current.exercises[0].sets[2].done = false
        let value = result([old, persisted], current: current)
        XCTAssertEqual(value.observations.count, 2); XCTAssertEqual(value.latest?.id, current.id)
        XCTAssertEqual(value.latest?.status, .inProgress); XCTAssertEqual(value.latest?.completedCount, 2); XCTAssertNil(value.comparison)
    }
    func testNewIncompleteSessionDoesNotFallBackToAnOlderSuccess() {
        let old = session()
        var latest = session(offset: 86400); latest.exercises[0].sets[2].done = false
        let value = result([old, latest])
        XCTAssertEqual(value.latest?.id, latest.id); XCTAssertEqual(value.latest?.status, .incomplete); XCTAssertNil(value.comparison)
    }
    func testDurationAndComplexTargetsAreNotRepGoals() {
        for text in ["AMRAP", "6/8/10", "8 per lato"] {
            var saved = session(); saved.exercises[0].exercise.reps = text
            XCTAssertEqual(result([saved]).latest?.status, .uninterpreted)
        }
        var hold = exercise; hold.isometric = true; hold.reps = "30 s"
        var saved = session(); saved.exercises[0].exercise = hold
        XCTAssertEqual(result([saved], exercise: hold).latest?.status, .uninterpreted)
    }
    func testBackoffDropSetsAndMixedDurationAreNotFlattenedIntoWorkingGoals() {
        for kind in [TrainingSetKind.backoff, .dropSet] {
            var saved = session(); saved.exercises[0].sets[1].kind = kind
            XCTAssertEqual(result([saved]).latest?.status, .uninterpreted)
        }
        var mixed = session(); mixed.exercises[0].sets[1].durationSeconds = 30
        XCTAssertEqual(result([mixed]).latest?.status, .uninterpreted)
    }
    func testInvalidCompletedValuesCannotCreateACompletedGoal() {
        for load in [Double.nan, .infinity, -1, 2001] {
            var saved = session(); saved.exercises[0].sets[1].kg = load
            XCTAssertEqual(result([saved]).latest?.status, .incomplete)
        }
        var saved = session(); saved.exercises[0].sets[1].reps = 1001
        XCTAssertEqual(result([saved]).latest?.status, .incomplete)
        saved.exercises[0].sets[1].reps = 0
        XCTAssertEqual(result([saved]).latest?.status, .incomplete)
    }
    func testComparisonUsesTheNearestEarlierMatchingPrescriptionAndLoads() {
        let old = session([6, 6, 6])
        var differentLoad = session(offset: 86400); differentLoad.exercises[0].sets[1].kg = 45
        let latest = session(offset: 172800)
        let value = result([latest, old, differentLoad])
        XCTAssertEqual(value.comparison?.previousID, old.id); XCTAssertEqual(value.comparison?.repDelta, 6)
        XCTAssertEqual(result([old, differentLoad]).comparison?.previousID, nil)
    }
    func testPhaseChangesAreNotPerformanceLossOrAutomaticLoadSuggestions() {
        for phase in [TrainingPhase.deload, .returning] {
            let old = session(), latest = session([6, 6, 6], offset: 86400, phase: phase)
            let value = result([old, latest])
            XCTAssertEqual(value.latest?.phase, phase); XCTAssertEqual(value.latest?.status, .inRange); XCTAssertNil(value.comparison)
        }
        let old = session(phase: nil), latest = session(offset: 86400, phase: .loading)
        XCTAssertNil(result([old, latest]).comparison)
        XCTAssertNotNil(result([old, session(offset: 86400, phase: nil)]).comparison)
    }
    func testChangedTargetsSetsRestTypesAndInstructionsCannotBeComparedDirectly() {
        let old = session([6, 6, 6])
        var target = session(offset: 86400); target.exercises[0].exercise.reps = "8–10"
        var count = session([8, 8], offset: 86400); count.exercises[0].exercise.sets = 2
        var rest = session(offset: 86400); rest.exercises[0].sets[0].restSeconds = 90
        var type = session(offset: 86400); type.exercises[0].sets[0].kind = .superset
        var failure = session(offset: 86400); failure.exercises[0].sets[0].toFailure = true
        var group = session(offset: 86400); group.exercises[0].sets[0].supersetGroup = "A"
        var notes = session(offset: 86400); notes.exercises[0].exercise.coachNotes = "Tempo diverso TEST"
        for latest in [target, count, rest, type, failure, group, notes] { XCTAssertNil(result([old, latest]).comparison) }
    }
    func testSameIDWithChangedNameCatalogOrSideModeDoesNotMixVariants() {
        let old = session()
        var renamed = exercise; renamed.name = "Altro movimento TEST"
        var catalog = exercise; catalog.catalogID = "other-variant"
        var unknown = exercise; unknown.catalogID = nil
        var side = exercise; side.separateSides = true
        for variant in [renamed, catalog, unknown, side] { XCTAssertTrue(result([old], exercise: variant).observations.isEmpty) }
        var otherID = exercise; otherID.id = "another-id"
        XCTAssertTrue(result([old], exercise: otherID).observations.isEmpty)
    }
    func testEqualDateDoesNotInventChronologicalProgressAndInvalidTimingIsExcluded() {
        XCTAssertNil(result([session(), session([6, 6, 6])]).comparison)
        var invalid = session(); invalid.end = invalid.start.addingTimeInterval(-1)
        XCTAssertTrue(result([invalid]).observations.isEmpty)
    }
    func testSelectedHistoricalSessionNeverComparesAgainstItsFuture() {
        let old = session([6, 6, 6]), selected = session(offset: 86400), future = session([9, 9, 9], offset: 172800)
        let value = result([old, selected, future], current: selected)
        XCTAssertEqual(value.latest?.id, selected.id); XCTAssertEqual(value.comparison?.previousID, old.id)
        XCTAssertEqual(value.comparison?.repDelta, 6)
    }
    func testExplicitPerSideModeRemainsUninterpretedRatherThanGuessingRepUnits() {
        var variant = exercise; variant.separateSides = true
        var saved = session(); saved.exercises[0].exercise = variant
        XCTAssertEqual(result([saved], exercise: variant).latest?.status, .uninterpreted)
    }
    func testZeroPrescribedSetsCannotProduceAVacuouslyReachedGoal() {
        var variant = exercise; variant.sets = 0
        var saved = session([]); saved.exercises[0].exercise = variant
        XCTAssertEqual(result([saved], exercise: variant).latest?.status, .uninterpreted)
    }
    func testGraphsCanUseTheSameExactVariantFilterWithoutChangingRecordedMetrics() {
        let matching = session()
        var variant = session(offset: 86400); variant.exercises[0].exercise.catalogID = "another-variant"
        variant.exercises[0].sets[0].kg = 100
        let library = TrainingLibrary(sessions: [matching, variant])
        let filtered = ExerciseProgress.calculate(exerciseID: exercise.id, library: library, exercise: exercise)
        XCTAssertEqual(filtered.performances.count, 1); XCTAssertEqual(filtered.bestLoad, 40)
        XCTAssertEqual(filtered.bestVolume, 960)
        XCTAssertEqual(library.sessions, [matching, variant])
        // Existing ID-only callers keep their established API until supplied a variant.
        XCTAssertEqual(ExerciseProgress.calculate(exerciseID: exercise.id, library: library).performances.count, 2)
    }
    func testWarningsRemainIndependentOfNumericalSuccessAndCalculationDoesNotMutateData() throws {
        let saved = session()
        let concern = TrainingConcern(area: "Zona TEST", observedAt: now, exercises: [.init(exercise)], createdAt: now, updatedAt: now)
        let library = TrainingLibrary(sessions: [saved], concerns: [concern])
        let before = try JSONEncoder().encode(library)
        let value = TrainingRepProgression.calculate(exercise: exercise, library: library)
        XCTAssertEqual(value.activeConcernCount, 1); XCTAssertEqual(value.latest?.status, .atUpper)
        XCTAssertEqual(library.sessions, [saved]); XCTAssertTrue(library.concerns?.first?.isActive == true)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let restored = try JSONDecoder().decode(TrainingLibrary.self, from: before)
        XCTAssertEqual(try encoder.encode(library), try encoder.encode(restored))
    }
}
